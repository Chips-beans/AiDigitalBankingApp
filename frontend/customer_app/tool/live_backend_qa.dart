// Opt-in: run `flutter test tool/live_backend_qa.dart` with the local API and Mailpit running.
// Creates one uniquely named, unfunded QA customer. Never use against production.
import 'dart:convert';

import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/core/network/api_client.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/auth/data/auth_gateway.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('local API signup, OTP rejection, restore/rotate, logout and subsequent login', () async {
    final config = AppConfig(
      apiBaseUrl: 'http://127.0.0.1:8080/api/v1',
      environment: 'dev',
    );
    final client = ApiClient(config);
    final mail = http.Client();
    final gateway = HttpAuthGateway(client);
    final vault = MemorySessionVault();
    var now = DateTime.now();
    var session = SessionController(gateway, vault, clock: () => now);
    final suffix = now.microsecondsSinceEpoch;
    final email = 'f2.contract.$suffix@example.test';
    final username = 'f2.contract.$suffix';
    addTearDown(() async {
      if (session.phase == SessionPhase.signedIn) await session.signOut();
      session.dispose();
      client.close();
      mail.close();
    });
    Future<String> code(String purpose) async {
      for (var attempt = 0; attempt < 30; attempt++) {
        final response = await mail.get(
          Uri.http('127.0.0.1:8025', '/api/v1/search', {'query': 'to:$email'}),
        );
        for (final item
            in (jsonDecode(response.body) as Map)['messages'] as List) {
          final response = await mail.get(
            Uri.http('127.0.0.1:8025', '/api/v1/message/${item['ID']}'),
          );
          final message = jsonDecode(response.body) as Map;
          if (!(message['Subject'] as String).contains(purpose)) continue;
          final match = RegExp(r'code is ([0-9]{6})')
              .firstMatch(message['Text'] as String);
          if (match != null) return match.group(1)!;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      throw StateError('Local OTP did not arrive');
    }

    await session.initialize();
    expect(
      await session.begin(
        email: email,
        password: 'QaFoundation2!',
        username: username,
        register: true,
      ),
      true,
    );
    final signupCode = await code('SIGNUP');
    final wrongCode = signupCode == '000000' ? '000001' : '000000';
    expect(await session.verifyCode(wrongCode), false);
    expect(session.failure!.code, 'OTP_INVALID');
    expect(await session.verifyCode(signupCode), true);
    expect(session.identity!.username, username);
    final before = await vault.readRefreshToken();
    session.dispose();
    session = SessionController(gateway, vault, clock: () => now);
    await session.initialize();
    expect(session.phase, SessionPhase.signedIn);
    expect(await vault.readRefreshToken() != before, true);
    now = now.add(const Duration(minutes: 16));
    await Future.wait([session.checkIdentity(), session.checkIdentity()]);
    final activeRefresh = await vault.readRefreshToken();
    await session.signOut();
    expect(session.phase, SessionPhase.signedOut);
    expect(await vault.readRefreshToken(), null);
    await expectLater(
      gateway.refresh(activeRefresh!),
      throwsA(
        isA<ApiFailure>().having((e) => e.code, 'revoked', 'SESSION_INVALID'),
      ),
    );
    expect(
      await session.begin(
        email: email,
        password: 'WrongPassword!',
        register: false,
      ),
      true,
    );
    final loginCode = await code('LOGIN');
    expect(await session.verifyCode(loginCode), false);
    expect(session.failure!.code, 'AUTHENTICATION_FAILED');
    session.back();
    // Reuse the unconsumed LOGIN code after correcting credentials; no second OTP request.
    final pair = await gateway.authenticate({
      'usernameOrEmail': email,
      'password': 'QaFoundation2!',
      'otpCode': loginCode,
      'deviceFingerprint': await vault.installationId(),
      'deviceName': 'F2 local contract QA',
      'deviceType': 'TEST',
    }, register: false);
    expect((await gateway.me(pair.accessToken)).email, email);
    await gateway.logout(pair.accessToken);
    await expectLater(
      gateway.me(pair.accessToken),
      throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 401)),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
