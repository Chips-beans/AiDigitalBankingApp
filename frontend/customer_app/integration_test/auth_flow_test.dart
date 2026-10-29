// Local development only: Mailpit is a test helper, never an app dependency.
import 'dart:convert';

import 'package:customer_app/app/banking_app.dart';
import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/core/network/api_client.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/auth/data/auth_gateway.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real signup, native storage restoration/rotation, logout, login and server revocation',
    (tester) async {
      final config = AppConfig.fromEnvironment();
      if (config.environment != 'dev' || config.isDemo) {
        throw StateError('Use the development API for this test');
      }
      final host = Uri.parse(config.apiBaseUrl).host;
      final mailpit = Uri.parse(
        const String.fromEnvironment('MAILPIT_URL', defaultValue: '') == ''
            ? 'http://$host:8025'
            : const String.fromEnvironment('MAILPIT_URL'),
      );
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final email = 'f2.$suffix@example.test';
      final client = ApiClient(config);
      final gateway = HttpAuthGateway(client);
      final vault = SecureSessionVault('f2-integration-$suffix');
      var session = SessionController(gateway, vault, deviceType: 'ANDROID');
      addTearDown(() async {
        if (session.phase == SessionPhase.signedIn) await session.signOut();
        await vault.writeRefreshToken(null);
        session.dispose();
        client.close();
      });
      Future<void> tap(String label) async {
        final finder = find.text(label).evaluate().isNotEmpty
            ? find.text(label)
            : find.byTooltip(label);
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      Future<void> enter(String field, String value) async {
        final finder = find.byKey(ValueKey(field));
        await tester.ensureVisible(finder);
        await tester.enterText(finder, value);
      }

      Future<String> latestCode(String purpose) async {
        final inbox = http.Client();
        try {
          for (var attempt = 0; attempt < 30; attempt++) {
            final response = await inbox
                .get(
                  mailpit.replace(
                    path: '/api/v1/search',
                    queryParameters: {'query': 'to:$email'},
                  ),
                )
                .timeout(const Duration(seconds: 5));
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            for (final item in data['messages'] as List) {
              final message = await inbox
                  .get(mailpit.replace(path: '/api/v1/message/${item['ID']}'))
                  .timeout(const Duration(seconds: 5));
              final detail = jsonDecode(message.body) as Map<String, dynamic>;
              final text = detail['Text'] as String;
              if (!(detail['Subject'] as String).contains(purpose)) continue;
              final match = RegExp(r'code is ([0-9]{6})').firstMatch(text);
              if (match != null) return match.group(1)!;
            }
            await Future<void>.delayed(const Duration(milliseconds: 300));
          }
          throw StateError('No matching local OTP email arrived');
        } finally {
          inbox.close();
        }
      }

      await session.initialize();
      debugPrint('Native QA: secure storage initialized');
      await tester.pumpWidget(BankingApp(session: session, config: config));
      await tester.pumpAndSettle();
      await tap('Continue with Email');
      await enter('email', email);
      await tap('Send Code');
      expect(find.text('Verification code'), findsOneWidget);
      await enter('otpCode', await latestCode('CONTINUE'));
      await tap('Verify');
      await enter('firstName', 'Native');
      await enter('lastName', 'Customer');
      await tester.ensureVisible(find.byKey(const ValueKey('profile-consent')));
      await tester.tap(find.byKey(const ValueKey('profile-consent')));
      await tester.pumpAndSettle();
      await tap('Create Account');
      expect(session.phase, SessionPhase.signedIn);
      expect(session.identity!.email, email);
      debugPrint('Native QA: signup through the UI passed');
      final firstRefresh = await vault.readRefreshToken();
      final installation = await vault.installationId();
      expect(firstRefresh != null, true);
      // Recreate all session state and the native vault. No access token is carried over.
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      final reopenedVault = SecureSessionVault('f2-integration-$suffix');
      session = SessionController(
        gateway,
        reopenedVault,
        deviceType: 'ANDROID',
      );
      await session.initialize();
      expect(session.phase, SessionPhase.signedIn);
      expect(session.identity!.email, email);
      expect(await reopenedVault.readRefreshToken() != firstRefresh, true);
      expect(await reopenedVault.installationId(), installation);
      debugPrint('Native QA: vault recreation and refresh rotation passed');
      await tester.pumpWidget(BankingApp(session: session, config: config));
      await tester.pumpAndSettle();
      await tap('Profile');
      await tap('Sign out');
      expect(session.phase, SessionPhase.signedOut);
      expect(await vault.readRefreshToken(), null);
      // Back from the public root correctly exits Android. Exercise Back from
      // the login route instead, so the remaining native test stays foreground.
      await tap('Continue with Email');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('You’re signed in.'), findsNothing);
      expect(find.text('Continue with Email'), findsOneWidget);
      debugPrint('Native QA: logout and protected back navigation passed');
      await tap('Continue with Email');
      await enter('email', email);
      await tap('Send Code');
      await enter('otpCode', await latestCode('CONTINUE'));
      await tap('Verify');
      expect(session.phase, SessionPhase.signedIn);
      debugPrint('Native QA: login through the UI passed');
      // Revoke the exact server session externally, then ensure the app drops private state.
      final saved = await vault.readRefreshToken();
      final externallyRotated = await gateway.refresh(saved!);
      await gateway.logout(externallyRotated.accessToken);
      await session.refreshProfile();
      await tester.pumpAndSettle();
      expect(session.phase, SessionPhase.signedOut);
      expect(session.identity, null);
      expect(await vault.readRefreshToken(), null);
      expect(find.text('Your profile'), findsNothing);
      debugPrint('Native QA: server revocation cleared private state');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
