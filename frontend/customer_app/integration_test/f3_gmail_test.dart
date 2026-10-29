// Opt-in live Gmail QA. See docs/FOUNDATION_F3_IMPLEMENTATION.md.
// Never reads captured inboxes or invents OTPs. Manual codes use a loopback bridge.
import 'dart:convert';

import 'package:customer_app/app/banking_app.dart';
import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/core/network/api_client.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/accounts/account_gateway.dart';
import 'package:customer_app/features/accounts/accounts_controller.dart';
import 'package:customer_app/features/accounts/creation_store.dart';
import 'package:customer_app/features/auth/data/auth_gateway.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

/// Fault injection: server commits, then the client loses the creation response.
class LostCreationResponse implements AccountGateway {
  LostCreationResponse(this.real);
  final AccountGateway real;
  int posts = 0;
  @override
  Future<List<BankAccount>> list(String token, int page) =>
      real.list(token, page);
  @override
  Future<BankAccount> detail(String token, String number) =>
      real.detail(token, number);
  @override
  Future<List<RecentPosting>> recent(String token, String number) =>
      real.recent(token, number);
  @override
  Future<BankAccount> open(String token, String type, String currency) async {
    posts++;
    await real.open(token, type, currency);
    throw const ApiFailure('TIMEOUT', 'Creation response lost during QA.');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment('QA_F3_PHASE');
  const password = String.fromEnvironment('QA_F3_PASSWORD');
  const firstEmail = String.fromEnvironment('QA_F3_CUSTOMER1');
  const secondEmail = String.fromEnvironment('QA_F3_CUSTOMER2');
  const staffEmail = String.fromEnvironment('QA_F3_STAFF');
  const bridgeKey = String.fromEnvironment('QA_F3_BRIDGE_KEY');
  testWidgets('F3 Gmail Android acceptance: $phase', (tester) async {
    final config = AppConfig.fromEnvironment();
    if (!['seed', 'uncertain', 'restore', 'signedout'].contains(phase) ||
        password.isEmpty ||
        bridgeKey.isEmpty ||
        config.environment != 'dev' ||
        config.isDemo ||
        Uri.parse(config.apiBaseUrl).host != '10.0.2.2') {
      throw StateError(
        'Explicit local Android Gmail QA configuration required',
      );
    }
    final client = ApiClient(config, timeout: const Duration(seconds: 25));
    final auth = HttpAuthGateway(client);
    final accounts = HttpAccountGateway(client);
    final vault = SecureSessionVault('${config.apiBaseUrl}|f3-gmail-qa');
    final store = SecureCreationStore('${config.apiBaseUrl}|f3-gmail-qa');
    final session = SessionController(auth, vault, deviceType: 'ANDROID');
    const evidence = FlutterSecureStorage();
    final evidenceKey =
        'banking.qa.f3.${base64Url.encode(utf8.encode(config.apiBaseUrl))}';
    final bridge = http.Client();
    addTearDown(() {
      session.dispose();
      client.close();
      bridge.close();
    });
    Future<String> code(String email, String purpose) async {
      final headers = {
        'X-Qa-Bridge': bridgeKey,
        'Content-Type': 'application/json',
      };
      final origin = Uri.parse('http://10.0.2.2:8089');
      final request = await bridge.post(
        origin.replace(path: '/request'),
        headers: headers,
        body: jsonEncode({'email': email, 'purpose': purpose}),
      );
      if (request.statusCode != 200) {
        throw StateError('Manual QA bridge unavailable');
      }
      final identifier = (jsonDecode(request.body) as Map)['id'];
      debugPrint('F3 Gmail QA: awaiting $purpose code for $email');
      final deadline = DateTime.now().add(const Duration(minutes: 4));
      while (DateTime.now().isBefore(deadline)) {
        final response = await bridge.get(
          origin.replace(path: '/poll', queryParameters: {'id': '$identifier'}),
          headers: headers,
        );
        final value = (jsonDecode(response.body) as Map)['code'];
        if (value is String) return value;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      throw StateError('Manual Gmail OTP was not supplied before expiry');
    }

    Future<void> mount(SessionController controller) async {
      await tester.pumpWidget(
        BankingApp(
          key: ValueKey(controller),
          session: controller,
          config: config,
          accountGateway: accounts,
          creationStore: store,
        ),
      );
      await tester.pumpAndSettle();
      if (controller.phase == SessionPhase.signedIn) {
        await tester.tap(find.byTooltip('View accounts'));
        await tester.pumpAndSettle();
      }
    }

    Future<void> tap(String label) async {
      final finder = find.text(label).evaluate().isNotEmpty
          ? find.text(label)
          : find.byTooltip(label);
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> enter(String key, String text) =>
        tester.enterText(find.byKey(ValueKey(key)), text);
    Future<void> signup(
      SessionController controller,
      String email,
      String username,
    ) async {
      await mount(controller);
      await tap('Continue with Email');
      await enter('email', email);
      await tap('Send Code');
      expect(find.text('Verification code'), findsOneWidget);
      await enter('otpCode', await code(email, 'CONTINUE'));
      await tap('Verify');
      await enter('firstName', 'Gmail');
      await enter('lastName', 'Customer');
      await tester.ensureVisible(find.byKey(const ValueKey('profile-consent')));
      await tester.tap(find.byKey(const ValueKey('profile-consent')));
      await tester.pumpAndSettle();
      await tap('Create Account');
      expect(controller.phase, SessionPhase.signedIn);
      await tap('View accounts');
    }

    final previousRefresh = await vault.readRefreshToken();
    await session.initialize();
    if (phase == 'signedout') {
      expect(session.phase, SessionPhase.signedOut);
      expect(await vault.readRefreshToken(), null);
      await mount(session);
      expect(find.text('Continue with Email'), findsOneWidget);
      await evidence.delete(key: evidenceKey);
    } else if (phase == 'uncertain') {
      expect(session.phase, SessionPhase.signedIn);
      final gateway = LostCreationResponse(accounts);
      final model = AccountsController(session, gateway, store);
      try {
        await model.initialize();
        final before = model.accounts.length;
        expect(await model.open('CHECKING', 'USD'), false);
        expect(gateway.posts, 1);
        expect(model.uncertain, true);
        expect(await store.pending(session.identity!.userId), true);
        expect(model.accounts.length, before + 1);
        expect(await model.open('CHECKING', 'USD'), false);
        expect(gateway.posts, 1);
        final expected = jsonDecode(
          (await evidence.read(key: evidenceKey))!,
        ) as Map<String, dynamic>;
        expected['accountCount'] = model.accounts.length;
        await evidence.write(key: evidenceKey, value: jsonEncode(expected));
        await mount(session);
        expect(
          find.textContaining('An account-opening request may have completed'),
          findsOneWidget,
        );
      } finally {
        model.dispose();
      }
    } else if (phase == 'restore') {
      expect(session.phase, SessionPhase.signedIn);
      final expected =
          jsonDecode((await evidence.read(key: evidenceKey))!) as Map;
      expect(session.identity!.userId, expected['userId']);
      expect(session.identity!.sessionId, expected['sessionId']);
      expect(await vault.installationId(), expected['installation']);
      expect(await vault.readRefreshToken() != previousRefresh, true);
      final model = AccountsController(session, accounts, store);
      try {
        await model.initialize();
        expect(model.uncertain, true);
        expect(model.accounts.length, expected['accountCount']);
        expect(await model.open('CHECKING', 'USD'), false);
        expect(
          model.accounts.map((a) => a.number),
          contains(expected['account']),
        );
        await model.select(
          model.accounts.firstWhere((a) => a.number == expected['account']),
        );
        expect(model.selected!.balance.formatted, 'USD 25.50');
        expect(model.activity.single.amount.formatted, 'USD 25.50');
        // An explicit new-account decision is the only local resolution here.
        await model.allowNewAccount();
        expect(await store.pending(session.identity!.userId), false);
      } finally {
        model.dispose();
      }
      await mount(session);
      await tap('Profile');
      await tap('Sign out');
      expect(session.phase, SessionPhase.signedOut);
      expect(find.text('USD 25.50'), findsNothing);
      await tap('Continue with Email');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Continue with Email'), findsOneWidget);
      expect(find.text('USD 25.50'), findsNothing);
    } else {
      if (session.phase == SessionPhase.signedOut) {
        await signup(session, firstEmail, 'f3.gmail.customer1');
      } else {
        await mount(session);
      }
      final model = AccountsController(session, accounts, store);
      TokenPair? staff;
      try {
        await model.initialize();
        expect(model.accounts, isEmpty);
        expect(find.textContaining('You have no accounts yet'), findsOneWidget);
        await tap('Open account');
        await tap('Confirm open account');
        await model.refresh();
        expect(model.accounts.length, 1);
        final first = model.accounts.single;
        expect(first.balance.formatted, 'USD 0.00');
        await tap('View account details');
        expect(find.text(first.number), findsOneWidget);
        await tap('Activity');
        expect(find.text('No activity yet for this account.'), findsOneWidget);
        // Separate staff identity, authenticated with actual Gmail OTP.
        await auth.requestOtp(staffEmail, 'LOGIN');
        staff = await auth.authenticate({
          'usernameOrEmail': staffEmail,
          'password': password,
          'otpCode': await code(staffEmail, 'LOGIN'),
          'deviceFingerprint': 'f3-staff-android-qa',
          'deviceName': 'F3 staff QA',
          'deviceType': 'ANDROID',
        }, register: false);
        expect(
          (await auth.me(staff.accessToken)).roles,
          contains('ROLE_BANK_EMPLOYEE'),
        );
        final deposit = await client.request(
          'POST',
          '/transactions/deposit',
          accessToken: staff.accessToken,
          idempotencyKey: 'f3-gmail-${first.number}-fund-1',
          body: {
            'accountNumber': first.number,
            'amount': '25.50',
            'currency': 'USD',
            'remark': 'F3 local QA funding',
          },
        );
        expect((deposit['data'] as Map)['status'], 'SUCCESS');
        await model.refresh();
        expect(model.selected!.balance.formatted, 'USD 25.50');
        expect(model.activity.single.amount.formatted, 'USD 25.50');
        await tap('Refresh recent activity');
        expect(find.text('USD 25.50'), findsOneWidget);
        // A second customer signs up through the actual screens.
        final second = SessionController(
          auth,
          SecureSessionVault('${config.apiBaseUrl}|f3-gmail-qa-second'),
        );
        try {
          await second.initialize();
          await signup(second, secondEmail, 'f3.gmail.customer2');
          final secondAccounts = AccountsController(second, accounts, store);
          try {
            await secondAccounts.initialize();
            expect(secondAccounts.accounts, isEmpty);
            expect(await secondAccounts.open('CHECKING', 'KHR'), true);
            expect(secondAccounts.selected!.balance.formatted, 'KHR 0');
            final otherNumber = secondAccounts.selected!.number;
            await expectLater(
              session.authorizedRead(
                (token) => accounts.detail(token, otherNumber),
              ),
              throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 404)),
            );
            await expectLater(
              second.authorizedRead(
                (token) => accounts.recent(token, first.number),
              ),
              throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 404)),
            );
            for (final status in ['FROZEN', 'CLOSED']) {
              await client.request(
                'PATCH',
                '/accounts/$otherNumber/status',
                accessToken: staff.accessToken,
                body: {'status': status},
              );
              await secondAccounts.refresh();
              expect(secondAccounts.selected!.status, status);
            }
          } finally {
            secondAccounts.dispose();
          }
          await tap('Profile');
          await tap('Sign out');
          expect(find.text('Continue with Email'), findsOneWidget);
          // Verify Gmail LOGIN through the app after signup and logout.
          await tap('Continue with Email');
          await enter('email', secondEmail);
          await tap('Send Code');
          await enter('otpCode', await code(secondEmail, 'CONTINUE'));
          await tap('Verify');
          expect(second.phase, SessionPhase.signedIn);
          await tap('Profile');
          await tap('Sign out');
        } finally {
          await second.signOut();
          second.dispose();
        }
        // KHR and PAYROLL on first customer; never perform a customer transfer.
        expect(await model.open('PAYROLL', 'KHR'), true);
        await model.select(first);
        await mount(session);
        await tap('Activity');
        await tap('Refresh recent activity');
        expect(find.text('USD 25.50'), findsOneWidget);
        await evidence.write(
          key: evidenceKey,
          value: jsonEncode({
            'userId': session.identity!.userId,
            'sessionId': session.identity!.sessionId,
            'installation': await vault.installationId(),
            'account': first.number,
          }),
        );
      } finally {
        model.dispose();
        if (staff != null) await auth.logout(staff.accessToken);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    debugPrint('F3 Gmail QA: $phase passed');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
