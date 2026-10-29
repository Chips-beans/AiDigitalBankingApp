import 'dart:async';

import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/core/network/api_client.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/auth/data/auth_gateway.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:customer_app/features/auth/telegram_native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const redirect = 'https://app937652339-login.tg.dev/tglogin';
final flowId = 'A' * 43;

class TestNativeClient extends NativeTelegramClient {
  Completer<String>? response;
  int calls = 0, cancels = 0;
  @override
  bool get supported => true;
  @override
  Future<String> authorize({
    required String authorizationUrl,
    required String redirectUri,
    required String flowId,
  }) async {
    calls++;
    return response == null ? 'test-provider-code' : response!.future;
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }
}

class TestNativeGateway extends DemoAuthGateway
    implements NativeTelegramGateway {
  int starts = 0, exchanges = 0, logouts = 0;
  ApiFailure? exchangeFailure;
  Completer<TokenPair>? exchangeResponse;
  @override
  Future<Map<String, dynamic>> startNativeTelegram(
    Map<String, dynamic> device, {
    String? linkToken,
  }) async {
    starts++;
    expect(device['deviceType'], 'ANDROID');
    return {
      'flowId': flowId,
      'exchangeSecret': 'B' * 43,
      'expiresInSeconds': 300,
      'authorizationUrl': 'https://oauth.telegram.org/auth',
      'redirectUri': redirect,
    };
  }

  Future<TokenPair> tokens() =>
      verifyEmail({'email': 'native@example.test', 'otpCode': '123456'});
  @override
  Future<TokenPair> exchangeNativeTelegram(
    String flowId,
    String exchangeSecret,
    String code,
  ) async {
    exchanges++;
    expect(code, 'test-provider-code');
    if (exchangeFailure != null) throw exchangeFailure!;
    return exchangeResponse == null ? tokens() : exchangeResponse!.future;
  }

  @override
  Future<void> logout(String accessToken) async {
    logouts++;
    await super.logout(accessToken);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('only an exact callback with the active state supplies a code', () {
    expect(
      nativeTelegramCode('$redirect?state=$flowId&code=one', redirect, flowId),
      'one',
    );
    for (final uri in [
      'http://app937652339-login.tg.dev/tglogin?state=$flowId&code=one',
      'https://evil.example/tglogin?state=$flowId&code=one',
      '${redirect}extra?state=$flowId&code=one',
      '$redirect?state=other&code=one',
      '$redirect?state=$flowId',
      '$redirect?state=$flowId&state=$flowId&code=one',
      '$redirect?state=$flowId&code=one&code=two',
      '$redirect?state=$flowId&code=one#fragment',
    ]) {
      expect(
        () => nativeTelegramCode(uri, redirect, flowId),
        throwsA(isA<ApiFailure>()),
      );
    }
    expect(
      () => nativeTelegramCode(
        '$redirect?state=$flowId&error=access_denied',
        redirect,
        flowId,
      ),
      throwsA(
        isA<ApiFailure>().having((e) => e.code, 'code', 'TELEGRAM_CANCELLED'),
      ),
    );
  });

  test(
    'platform bridge validates its callback and sanitizes native errors',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          NativeTelegramClient.channel,
          null,
        ),
      );
      messenger.setMockMethodCallHandler(NativeTelegramClient.channel, (
        call,
      ) async {
        expect(call.method, 'authorize');
        expect((call.arguments as Map)['flowId'], flowId);
        return '$redirect?state=$flowId&code=one';
      });
      final client = NativeTelegramClient();
      expect(
        await client.authorize(
          authorizationUrl: 'https://oauth.telegram.org/auth',
          redirectUri: redirect,
          flowId: flowId,
        ),
        'one',
      );
      messenger.setMockMethodCallHandler(
        NativeTelegramClient.channel,
        (_) async => throw PlatformException(
          code: 'unexpected',
          message: 'sensitive provider detail',
        ),
      );
      await expectLater(
        client.authorize(
          authorizationUrl: 'https://oauth.telegram.org/auth',
          redirectUri: redirect,
          flowId: flowId,
        ),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.message,
            'message',
            isNot(contains('sensitive')),
          ),
        ),
      );
    },
  );

  test(
    'native login installs a secure session and resumes onboarding',
    () async {
      final gateway = TestNativeGateway();
      final native = TestNativeClient();
      final vault = MemorySessionVault();
      final session = SessionController(gateway, vault, nativeTelegram: native);
      addTearDown(session.dispose);
      await session.initialize();
      await session.continueTelegram();
      expect(gateway.exchanges, 1);
      expect(native.calls, 1);
      expect(session.phase, SessionPhase.signedIn);
      expect(session.identity!.profileComplete, false);
      expect(await vault.readRefreshToken(), isNotNull);
      await session.completeInformation('Dara', 'Sok');
      expect(session.identity!.profileComplete, true);
      await session.signOut();
      expect(await vault.readRefreshToken(), isNull);
    },
  );

  test(
    'cancellation suppresses a late callback without submitting an exchange',
    () async {
      final gateway = TestNativeGateway();
      final native = TestNativeClient()..response = Completer<String>();
      final session = SessionController(
        gateway,
        MemorySessionVault(),
        nativeTelegram: native,
      );
      addTearDown(session.dispose);
      await session.initialize();
      final login = session.continueTelegram();
      await Future<void>.delayed(Duration.zero);
      expect(native.calls, 1);
      session.cancelTelegram();
      native.response!.complete('test-provider-code');
      await login;
      expect(gateway.exchanges, 0);
      expect(session.phase, SessionPhase.signedOut);
      expect(session.telegramPending, false);
    },
  );

  test(
    'an uncertain exchange is sent once and requires new approval',
    () async {
      final gateway = TestNativeGateway()
        ..exchangeFailure = const ApiFailure(
          'NETWORK_ERROR',
          'Connection lost',
        );
      final session = SessionController(
        gateway,
        MemorySessionVault(),
        nativeTelegram: TestNativeClient(),
      );
      addTearDown(session.dispose);
      await session.initialize();
      await session.continueTelegram();
      expect(gateway.exchanges, 1);
      expect(gateway.starts, 1);
      expect(session.phase, SessionPhase.signedOut);
      expect(session.failure!.code, 'NETWORK_ERROR');
    },
  );

  test(
    'a session arriving after cancellation is revoked rather than installed',
    () async {
      final gateway = TestNativeGateway()
        ..exchangeResponse = Completer<TokenPair>();
      final session = SessionController(
        gateway,
        MemorySessionVault(),
        nativeTelegram: TestNativeClient(),
      );
      addTearDown(session.dispose);
      await session.initialize();
      final login = session.continueTelegram();
      await Future<void>.delayed(Duration.zero);
      expect(gateway.exchanges, 1);
      session.cancelTelegram();
      gateway.exchangeResponse!.complete(await gateway.tokens());
      await login;
      expect(gateway.logouts, 1);
      expect(session.phase, SessionPhase.signedOut);
    },
  );

  test(
    'HTTP gateway keeps native start/exchange separate and sends no password',
    () async {
      final paths = <String>[];
      final gateway = HttpAuthGateway(
        ApiClient(
          AppConfig(
            apiBaseUrl: 'https://bank.example.test/api/v1',
            environment: 'dev',
          ),
          client: MockClient((request) async {
            paths.add(request.url.path);
            expect(request.body, isNot(contains('password')));
            if (request.url.path.endsWith('/exchange')) {
              return http.Response(
              '{"success":true,"data":{"accessToken":"access","refreshToken":"refresh","expiresInMs":900000}}',
                200,
              );
            }
            expect(request.headers['Authorization'], 'Bearer owner');
          return http.Response('{"success":true,"data":{"flowId":"flow"}}', 200);
          }),
        ),
      );
      await gateway.startNativeTelegram({
        'deviceFingerprint': 'installation',
      }, linkToken: 'owner');
      await gateway.exchangeNativeTelegram(flowId, 'secret', 'code');
      expect(paths, [
        '/api/v1/auth/telegram/native/link/start',
        '/api/v1/auth/telegram/native/exchange',
      ]);
    },
  );
}
