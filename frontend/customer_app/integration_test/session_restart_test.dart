// Run through tool/verify_native_restart.ps1: each phase launches a new app process.
import 'dart:convert';

import 'package:customer_app/app/banking_app.dart';
import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/core/network/api_client.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/auth/data/auth_gateway.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment('QA_RESTART_PHASE');
  testWidgets('native cross-process session: $phase', (tester) async {
    if (!['seed', 'restore', 'signedout'].contains(phase)) {
      throw StateError('Use the native restart QA script');
    }
    final config = AppConfig.fromEnvironment();
    if (config.environment != 'dev' || config.isDemo) {
      throw StateError('Local development API required');
    }
    final client = ApiClient(config);
    final gateway = HttpAuthGateway(client);
    final vault = SecureSessionVault('${config.apiBaseUrl}|native-restart-qa');
    const evidence = FlutterSecureStorage();
    final evidenceKey =
        'banking.qa.restart.${base64Url.encode(utf8.encode(config.apiBaseUrl))}';
    Map<String, dynamic>? expected;
    if (phase != 'seed') {
      final saved = await evidence.read(key: evidenceKey);
      if (saved == null) {
        throw StateError('Run seed before restart verification');
      }
      expected = jsonDecode(saved) as Map<String, dynamic>;
      expect(await vault.installationId(), expected['installation']);
    }
    if (phase == 'seed') {
      // Dedicated QA namespace: discard only an older interrupted QA session.
      final previous = await vault.readRefreshToken();
      if (previous != null) {
        try {
          final pair = await gateway.refresh(previous);
          await gateway.logout(pair.accessToken);
        } catch (_) {
          /* Already expired. */
        }
        await vault.writeRefreshToken(null);
      }
    }
    final session = SessionController(gateway, vault, deviceType: 'ANDROID');
    addTearDown(() {
      session.dispose();
      client.close();
    });
    final previousRefresh = await vault.readRefreshToken();
    if (phase == 'restore') expect(previousRefresh != null, true);
    await session.initialize();
    debugPrint('Native restart QA: $phase initialized');
    if (phase == 'seed') {
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final email = 'f2.restart.$suffix@example.test';
      expect(
        await session.begin(
          email: email,
          password: 'QaFoundation2!',
          username: 'f2.restart.$suffix',
          register: true,
        ),
        true,
      );
      final inbox = http.Client();
      try {
        final origin = Uri.parse(config.apiBaseUrl).replace(
          port: 8025,
          path: '/api/v1/search',
          queryParameters: {'query': 'to:$email'},
        );
        String? code;
        for (var attempt = 0; attempt < 30 && code == null; attempt++) {
          final response = await inbox
              .get(origin)
              .timeout(const Duration(seconds: 5));
          for (final item
              in (jsonDecode(response.body) as Map)['messages'] as List) {
            final message = await inbox
                .get(
                  origin.replace(
                    path: '/api/v1/message/${item['ID']}',
                    query: '',
                  ),
                )
                .timeout(const Duration(seconds: 5));
            code = RegExp(r'code is ([0-9]{6})')
                .firstMatch((jsonDecode(message.body) as Map)['Text'] as String)
                ?.group(1);
            if (code != null) break;
          }
          if (code == null) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
        }
        if (code == null) throw StateError('No local QA OTP arrived');
        expect(await session.verifyCode(code), true);
        // QA evidence contains identity only; never copy a token into another key.
        await evidence.write(
          key: evidenceKey,
          value: jsonEncode({
            'installation': await vault.installationId(),
            'userId': session.identity!.userId,
            'username': session.identity!.username,
            'sessionId': session.identity!.sessionId,
          }),
        );
      } finally {
        inbox.close();
      }
    }
    if (phase == 'signedout') {
      expect(session.phase, SessionPhase.signedOut);
      expect(await vault.readRefreshToken(), null);
    } else {
      expect(session.phase, SessionPhase.signedIn);
      expect(session.identity!.username.startsWith('f2.restart.'), true);
      expect(await vault.readRefreshToken() != null, true);
      if (phase == 'restore') {
        expect(session.identity!.userId, expected!['userId']);
        expect(session.identity!.username, expected['username']);
        expect(session.identity!.sessionId, expected['sessionId']);
        expect(await vault.readRefreshToken() != previousRefresh, true);
        debugPrint(
          'Native restart QA: same identity and installation; token rotated',
        );
      }
    }
    await tester.pumpWidget(BankingApp(session: session, config: config));
    await tester.pumpAndSettle();
    if (phase == 'restore') {
      expect(find.byTooltip('Home'), findsOneWidget);
      await session.signOut();
      await tester.pumpAndSettle();
      expect(find.text('You’re signed in.'), findsNothing);
      expect(await vault.readRefreshToken(), null);
    }
    if (phase == 'signedout') {
      expect(find.text('Continue with Email'), findsOneWidget);
      await evidence.delete(key: evidenceKey);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    // seed intentionally leaves its refresh token in native storage for the next process.
    debugPrint('Native restart QA: $phase passed');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
