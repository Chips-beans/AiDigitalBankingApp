// Opt-in live Gmail + real API Android acceptance; no captured inbox or OTP bypass.
import 'dart:convert';

import 'package:customer_app/app/banking_app.dart';
import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/core/network/api_client.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/accounts/account_gateway.dart';
import 'package:customer_app/features/accounts/creation_store.dart';
import 'package:customer_app/features/auth/data/auth_gateway.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:customer_app/features/transactions/transaction_gateway.dart';
import 'package:customer_app/features/transactions/transfer_models.dart';
import 'package:customer_app/features/transactions/transfer_store.dart';
import 'package:customer_app/shared/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

class LostTransferResponse implements TransactionGateway {
  LostTransferResponse(this.real);
  final TransactionGateway real;
  bool dropNext = false;
  final List<SavedTransfer> posts = [];
  @override
  Future<RecentPosting> transfer(String token, SavedTransfer intent, {String? pinProof}) async {
    posts.add(intent);
    final receipt = await real.transfer(token, intent, pinProof: pinProof);
    if (dropNext) {
      dropNext = false;
      throw const ApiFailure('TIMEOUT', 'Response deliberately lost for QA.');
    }
    return receipt;
  }

  @override
  Future<PostingPage> history(String token, String account, int page) =>
      real.history(token, account, page);
  @override
  Future<RecentPosting> detail(
    String token,
    String account,
    String reference,
  ) => real.detail(token, account, reference);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment('QA_F4_PHASE');
  const password = String.fromEnvironment('QA_F3_PASSWORD');
  const firstEmail = String.fromEnvironment('QA_F3_CUSTOMER1');
  const secondEmail = String.fromEnvironment('QA_F3_CUSTOMER2');
  const bridgeKey = String.fromEnvironment('QA_F3_BRIDGE_KEY');
  testWidgets('F4 Gmail transfer acceptance: $phase', (tester) async {
    final config = AppConfig.fromEnvironment();
    if (!['seed', 'response_loss', 'restore', 'signedout'].contains(phase) ||
        password.isEmpty ||
        bridgeKey.isEmpty ||
        config.isDemo ||
        config.environment != 'dev' ||
        Uri.parse(config.apiBaseUrl).host != '10.0.2.2') {
      throw StateError(
        'Explicit local Gmail Android QA configuration required',
      );
    }
    final client = ApiClient(config, timeout: const Duration(seconds: 25));
    final auth = HttpAuthGateway(client), accounts = HttpAccountGateway(client);
    final real = HttpTransactionGateway(client),
        transactions = LostTransferResponse(HttpTransactionGateway(client));
    final namespace = '${config.apiBaseUrl}|f4-gmail-qa';
    final vault = SecureSessionVault(namespace),
        secondVault = SecureSessionVault('$namespace-second');
    final store = SecureTransferStore(namespace);
    final session = SessionController(auth, vault, deviceType: 'ANDROID');
    final second = SessionController(auth, secondVault, deviceType: 'ANDROID');
    final creation = SecureCreationStore(namespace);
    final inboxBridge = http.Client();
    const evidence = FlutterSecureStorage();
    final evidenceKey =
        'banking.qa.f4.${base64Url.encode(utf8.encode(config.apiBaseUrl))}';
    addTearDown(() {
      session.dispose();
      second.dispose();
      client.close();
      inboxBridge.close();
    });
    Future<String> code(String email) async {
      final headers = {
        'X-Qa-Bridge': bridgeKey,
        'Content-Type': 'application/json',
      };
      final origin = Uri.parse('http://10.0.2.2:8089');
      final response = await inboxBridge.post(
        origin.replace(path: '/request'),
        headers: headers,
        body: jsonEncode({'email': email, 'purpose': 'LOGIN'}),
      );
      expect(response.statusCode, 200);
      final id = (jsonDecode(response.body) as Map)['id'];
      debugPrint('F4 Gmail QA: awaiting LOGIN code for $email');
      final deadline = DateTime.now().add(const Duration(minutes: 4));
      while (DateTime.now().isBefore(deadline)) {
        final poll = await inboxBridge.get(
          origin.replace(path: '/poll', queryParameters: {'id': '$id'}),
          headers: headers,
        );
        final value = (jsonDecode(poll.body) as Map)['code'];
        if (value is String) return value;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      throw StateError('Gmail code not supplied before expiry');
    }

    Future<void> mount(SessionController active) async {
      await tester.pumpWidget(
        BankingApp(
          key: ValueKey(active),
          session: active,
          config: config,
          accountGateway: accounts,
          creationStore: creation,
          transactionGateway: transactions,
          transferStore: store,
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tap(String text) async {
      if (find.byTooltip('View accounts').evaluate().isNotEmpty &&
          find.text(text).evaluate().isEmpty &&
          !{'Home', 'Activity', 'Profile'}.contains(text)) {
        await tester.tap(find.byTooltip('View accounts'));
        await tester.pumpAndSettle();
      }
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      Finder action() => find.text(text).evaluate().isNotEmpty
          ? find.text(text).first
          : find.byTooltip(text).first;
      while (action().evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
      }
      expect(action(), findsWidgets, reason: 'Expected action: $text');
      await tester.ensureVisible(action());
      await tester.tap(action());
      await tester.pumpAndSettle();
    }

    Future<void> enter(String key, String text) async {
      final field = find.byKey(ValueKey(key));
      await tester.ensureVisible(field);
      await tester.enterText(field, text);
    }

    Future<void> login(SessionController active, String email) async {
      await mount(active);
      await tap('Sign in');
      await enter('email', email);
      await enter('password', password);
      await tap('Send email code');
      expect(find.text('Check your email'), findsOneWidget);
      await enter('otpCode', await code(email));
      await tap('Sign in');
      expect(active.phase, SessionPhase.signedIn);
    }

    Future<List<BankAccount>> own(SessionController active) =>
        active.authorizedRead((token) => accounts.list(token, 0));
    Future<BankAccount> balance(SessionController active, String number) =>
        active.authorizedRead((token) => accounts.detail(token, number));
    Future<void> loseResponse(BankAccount source, BankAccount recipient) async {
      await mount(session);
      await tap(source.label);
      await tap('Review saved transfer');
      await tap('Done — return to transfer entry');
      await enter('transfer-destination', recipient.number);
      await enter('transfer-amount', '1.00');
      await enter('transfer-remark', 'F4 response-loss QA');
      await tap('Review transfer');
      transactions.dropNext = true;
      await tap('Confirm and send');
      expect(find.text('Transfer outcome unknown'), findsOneWidget);
      final unresolved = (await store.read(session.identity!.userId))!;
      expect(unresolved.unresolved, true);
      final history = await session.authorizedRead(
        (token) => real.history(token, source.number, 0),
      );
      expect(
        history.content.where((p) => p.remark == 'F4 response-loss QA'),
        hasLength(1),
      );
      await evidence.write(
        key: evidenceKey,
        value: jsonEncode({
          'userId': session.identity!.userId,
          'sessionId': session.identity!.sessionId,
          'installation': await vault.installationId(),
          'key': unresolved.key,
          'payload': unresolved.draft.payload,
          'reference': history.content
              .firstWhere((p) => p.remark == 'F4 response-loss QA')
              .reference,
          'source': source.number,
          'recipient': recipient.number,
          'sourceAfter': (source.balance.minorUnits - BigInt.from(100))
              .toString(),
          'recipientAfter': (recipient.balance.minorUnits + BigInt.from(100))
              .toString(),
        }),
      );
    }

    final previous = await vault.readRefreshToken();
    await session.initialize();
    await second.initialize();
    if (phase == 'seed') {
      if (second.phase != SessionPhase.signedIn) {
        await login(second, secondEmail);
      } else {
        await mount(second);
      }
      // A new active USD account is separate from F3's CLOSED KHR account.
      final before = await own(second);
      await tap('Open account');
      await tap('Confirm open account');
      final recipient = (await own(second))
          .singleWhere((a) => !before.any((old) => old.number == a.number));
      expect(recipient.currency, 'USD');
      expect(recipient.status, 'ACTIVE');
      if (session.phase != SessionPhase.signedIn) {
        await login(session, firstEmail);
      } else {
        await mount(session);
      }
      final firstAccounts = await own(session);
      final source = firstAccounts.firstWhere(
        (a) =>
            a.currency == 'USD' && a.status == 'ACTIVE' && a.type == 'SAVINGS',
      );
      final privateRecipient = firstAccounts.firstWhere(
        (a) =>
            a.currency == 'USD' &&
            a.status == 'ACTIVE' &&
            a.number != source.number,
      );
      final khr = firstAccounts.firstWhere(
        (a) => a.currency == 'KHR' && a.status == 'ACTIVE',
      );
      if (source.balance.minorUnits < BigInt.from(700)) {
        throw StateError(
          'QA source needs at least USD 7.00 from authorized staff funding',
        );
      }
      expect(await store.read(session.identity!.userId), null);
      await tap(source.label);
      await tap('Transfer');
      await enter('transfer-destination', recipient.number);
      await enter('transfer-amount', '5.00');
      await enter('transfer-remark', 'F4 Gmail UI transfer');
      await tap('Review transfer');
      expect(transactions.posts, isEmpty);
      await tap('Confirm and send');
      expect(find.text('Transfer confirmed'), findsOneWidget);
      final confirmed = (await store.read(session.identity!.userId))!;
      expect(confirmed.outcome, 'success');
      expect(
        (await balance(session, source.number)).balance.minorUnits,
        source.balance.minorUnits - BigInt.from(500),
      );
      expect(
        (await balance(second, recipient.number)).balance.minorUnits,
        BigInt.from(500),
      );
      final replay = await session.authorizedMutation(
        (token) => real.transfer(token, confirmed),
      );
      expect(replay.reference, confirmed.reference);
      expect(
        (await balance(session, source.number)).balance.minorUnits,
        source.balance.minorUnits - BigInt.from(500),
      );
      await tap('Activity');
      await tap('Refresh recent activity');
      expect(find.text(confirmed.reference!), findsOneWidget);
      await tap('View transaction details');
      expect(find.text('Remark: F4 Gmail UI transfer'), findsOneWidget);
      // Rejections must leave the account unchanged.
      final after = await balance(session, source.number);
      for (final bad in [
        TransferDraft(
          source.number,
          recipient.number,
          Money.parse('9999999999999.99', 'USD'),
          null,
        ),
        TransferDraft(source.number, khr.number, Money.parse('1', 'USD'), null),
        TransferDraft(
          source.number,
          before.firstWhere((a) => a.status == 'CLOSED').number,
          Money.parse('1', 'USD'),
          null,
        ),
      ]) {
        await expectLater(
          session.authorizedMutation(
            (token) => real.transfer(token, SavedTransfer.confirmed(bad)),
          ),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.code,
              'rejection',
              anyOf(
                'INSUFFICIENT_FUNDS',
                'CURRENCY_MISMATCH',
                'ACCOUNT_INACTIVE',
              ),
            ),
          ),
        );
        expect(
          (await balance(session, source.number)).balance.minorUnits,
          after.balance.minorUnits,
        );
      }
      // An unrelated customer must not access an own-account transfer's detail.
      final privateTransfer = SavedTransfer.confirmed(
        TransferDraft(
          source.number,
          privateRecipient.number,
          Money.parse('1', 'USD'),
          'F4 private detail QA',
        ),
      );
      final privatePosting = await session.authorizedMutation(
        (token) => real.transfer(token, privateTransfer),
      );
      await expectLater(
        second.authorizedRead(
          (token) =>
              real.detail(token, recipient.number, privatePosting.reference),
        ),
        throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 404)),
      );
      await expectLater(
        second.authorizedRead((token) => real.history(token, source.number, 0)),
        throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 404)),
      );
      await mount(second);
      await tap(recipient.label);
      await tap('Activity');
      await tap('Refresh recent activity');
      expect(find.text(confirmed.reference!), findsOneWidget);
      await tap('View transaction details');
      expect(find.text('Incoming · SUCCESS'), findsOneWidget);
      await loseResponse(
        await balance(session, source.number),
        await balance(second, recipient.number),
      );
    } else if (phase == 'response_loss') {
      expect(session.phase, SessionPhase.signedIn);
      expect(second.phase, SessionPhase.signedIn);
      final confirmed = (await store.read(session.identity!.userId))!;
      expect(confirmed.outcome, 'success');
      await loseResponse(
        await balance(session, confirmed.draft.source),
        await balance(second, confirmed.draft.destination),
      );
    } else if (phase == 'restore') {
      expect(session.phase, SessionPhase.signedIn);
      final expected =
          jsonDecode((await evidence.read(key: evidenceKey))!) as Map;
      expect(session.identity!.userId, expected['userId']);
      expect(session.identity!.sessionId, expected['sessionId']);
      expect(await vault.installationId(), expected['installation']);
      expect(await vault.readRefreshToken() != previous, true);
      await mount(session);
      expect(transactions.posts, isEmpty);
      await tap('Review saved transfer');
      expect(find.text('Transfer outcome unknown'), findsOneWidget);
      final restored = (await store.read(session.identity!.userId))!;
      expect(restored.key, expected['key']);
      expect(restored.draft.payload, expected['payload']);
      await tap('Retry this exact transfer');
      expect(transactions.posts.length, 1);
      expect(transactions.posts.single.key, expected['key']);
      expect(transactions.posts.single.draft.payload, expected['payload']);
      expect(find.text('Transfer confirmed'), findsOneWidget);
      final resolved = (await store.read(session.identity!.userId))!;
      expect(resolved.reference, expected['reference']);
      expect(
        (await balance(
          session,
          expected['source'] as String,
        )).balance.minorUnits.toString(),
        expected['sourceAfter'],
      );
      final history = await session.authorizedRead(
        (token) => real.history(token, expected['source'] as String, 0),
      );
      expect(
        history.content.where((p) => p.reference == expected['reference']),
        hasLength(1),
      );
      expect(second.phase, SessionPhase.signedIn);
      expect(
        (await balance(
          second,
          expected['recipient'] as String,
        )).balance.minorUnits.toString(),
        expected['recipientAfter'],
      );
      await tap('Done — return to transfer entry');
      expect(await store.read(session.identity!.userId), null);
      await mount(second);
      final receivedAccount = (await own(second))
          .firstWhere((a) => a.number == expected['recipient']);
      await tap(receivedAccount.label);
      await tap('Activity');
      await tap('Refresh recent activity');
      expect(find.text(expected['reference'] as String), findsOneWidget);
      await tap('Profile');
      await tap('Sign out');
      await mount(session);
      await tap('Profile');
      await tap('Sign out');
      expect(find.textContaining('TXN-'), findsNothing);
      expect(await vault.readRefreshToken(), null);
      await tap('Sign in');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Continue with Email'), findsOneWidget);
    } else {
      expect(session.phase, SessionPhase.signedOut);
      expect(second.phase, SessionPhase.signedOut);
      expect(await vault.readRefreshToken(), null);
      await mount(session);
      expect(find.text('Continue with Email'), findsOneWidget);
      await evidence.delete(key: evidenceKey);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    debugPrint('F4 Gmail QA: $phase passed');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
