import 'dart:async';

import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/core/network/api_client.dart';
import 'package:customer_app/features/accounts/account_gateway.dart';
import 'package:customer_app/features/accounts/accounts_controller.dart';
import 'package:customer_app/features/accounts/creation_store.dart';
import 'package:customer_app/features/accounts/presentation/wallet_detail_screen.dart';
import 'package:customer_app/features/accounts/presentation/accounts_shell.dart';
import 'package:customer_app/features/home/home_unlock_target.dart';
import 'package:customer_app/features/transactions/transfer_store.dart';
import 'package:customer_app/features/transactions/history_controller.dart';
import 'package:customer_app/features/transactions/presentation/transaction_detail_screen.dart';
import 'package:customer_app/shared/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'accounts_test.dart' show FakeAccounts;
import 'qr_pairs_test.dart' show signedSession;
import 'transactions_test.dart' show FakeTransactions, funded;

RecentPosting detailPosting(
  String currency, {
  String reference = 'KSR261104000128',
  bool incoming = false,
  DateTime? at,
  String status = 'SUCCESS',
}) => RecentPosting(
  reference: reference,
  source: incoming ? '1231231231' : funded(currency == 'USD' ? 1 : 2).number,
  destination: incoming
      ? funded(currency == 'USD' ? 1 : 2).number
      : '1231231231',
  amount: Money.parse(currency == 'USD' ? '3.00' : '1947', currency),
  fee: Money.parse('0', currency),
  type: 'TRANSFER',
  status: status,
  createdAt: at ?? DateTime.utc(2026, 11, 4, 14, 28),
  remark: 'Lunch payment',
  operation: 'MERCHANT_QR_PAYMENT',
  sourceName: 'SOKUNBANHA KAY',
  destinationName: 'LUJ KJ DIGITAL 4',
);

class DetailRig {
  DetailRig(this.accounts, this.history, this.api);
  final AccountsController accounts;
  final HistoryController history;
  final FakeTransactions api;
  static Future<DetailRig> create({String currency = 'USD'}) async {
    final session = await signedSession();
    final accounts = AccountsController(
      session,
      FakeAccounts()
        ..data = [
          funded(1, balance: '168'),
          funded(2, currency: 'KHR', balance: '2000'),
        ],
      MemoryCreationStore(),
    );
    await accounts.initialize();
    await accounts.select(
      accounts.accounts.firstWhere((a) => a.currency == currency),
    );
    final api = FakeTransactions()
      ..historyItems = [
        detailPosting(currency),
        detailPosting(
          currency,
          reference: 'KSR261104000129',
          incoming: true,
          at: DateTime.utc(2026, 11, 3, 18),
        ),
        detailPosting(
          currency,
          reference: 'KSR261103000130',
          at: DateTime.utc(2026, 11, 3, 12),
        ),
      ];
    api.onDetail = (_, ref) async =>
        api.historyItems.firstWhere((p) => p.reference == ref);
    final history = HistoryController(session, accounts, api);
    await history.refresh();
    await history.openDetail(api.historyItems.first.reference);
    return DetailRig(accounts, history, api);
  }

  void dispose() {
    history.dispose();
    accounts.dispose();
    accounts.session.dispose();
  }
}

Widget detailsHarness(
  Widget child, {
  AppPreferences? preferences,
  Size? size,
  double scale = 1,
  bool dark = false,
  EdgeInsets padding = EdgeInsets.zero,
}) {
  final prefs = preferences ?? AppPreferences();
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: prefs.locale,
    supportedLocales: const [Locale('en'), Locale('km')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: AppTheme.build(
      dark ? Brightness.dark : Brightness.light,
      locale: prefs.locale,
    ),
    home: AppPreferencesScope(
      preferences: prefs,
      child: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: size,
            padding: padding,
            textScaler: TextScaler.linear(scale),
          ),
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'PIN continuation waits for account loading and resolves the KHR receipt wallet',
    (tester) async {
      final session = await signedSession();
      addTearDown(session.dispose);
      final gate = Completer<BankAccount>();
      final khr = funded(2, currency: 'KHR', balance: '2000');
      final gateway = FakeAccounts()..data = [funded(1, balance: '168'), khr];
      gateway.onDetail = (number) async =>
          number == khr.number ? khr : gate.future;
      gateway.onRecent = (number) async =>
          number == khr.number ? [detailPosting('KHR')] : [];
      final calls = <String>[];
      final api = FakeTransactions()
        ..onDetail = (number, reference) async {
          calls.add(number);
          return detailPosting('KHR');
        };
      await tester.pumpWidget(
        detailsHarness(
          AccountsShell(
            session: session,
            gateway: gateway,
            store: MemoryCreationStore(),
            transactions: api,
            transferStore: MemoryTransferStore(),
            transfersEnabled: true,
            initialTarget: const HomeUnlockTarget(
              'transaction',
              reference: 'KSR261104000128',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(calls, isEmpty);
      gate.complete(funded(1, balance: '168'));
      await tester.pumpAndSettle();
      expect(calls, [khr.number]);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('receipt-amount'))).data,
        '−1947 KHR',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'pending converted receipt keeps wallet and original currencies distinct',
    (tester) async {
      final rig = await DetailRig.create(currency: 'KHR');
      addTearDown(rig.dispose);
      rig.history.detail = RecentPosting.fromJson({
        'referenceNumber': 'KSR-FX-PENDING',
        'sourceAccountNumber': '1231231231',
        'destinationAccountNumber': '1000000002',
        'amount': '42.00',
        'currency': 'USD',
        'creditAmount': '168000',
        'creditCurrency': 'KHR',
        'fee': '0.00',
        'transactionType': 'TRANSFER',
        'status': 'PENDING',
        'createdAt': '2026-11-04T14:28:00Z',
        'exchangeRate': '4000',
        'sourceName': 'Sender',
        'destinationName': 'Owner',
      }, '1000000002');
      await tester.pumpWidget(
        detailsHarness(
          TransactionDetailScreen(
            accounts: rig.accounts,
            history: rig.history,
            reference: 'KSR-FX-PENDING',
            ownerName: 'Owner',
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('receipt-amount'))).data,
        '+168000 KHR',
      );
      expect(find.text('42.00 USD'), findsOneWidget);
      expect(find.text('Status: Pending'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('receipt-view-more')),
      );
      await tester.tap(find.byKey(const ValueKey('receipt-view-more')));
      await tester.pumpAndSettle();
      expect(find.text('KHR 168,000'), findsOneWidget);
      expect(find.text('USD 0.00'), findsOneWidget);
      expect(find.text('4000'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'wallet activity groups in Phnom Penh time and opens the owned posting',
    (tester) async {
      final rig = await DetailRig.create(currency: 'KHR');
      addTearDown(rig.dispose);
      String? opened;
      await tester.pumpWidget(
        detailsHarness(
          WalletDetailScreen(
            accounts: rig.accounts,
            history: rig.history,
            ownerName: 'SENG SOVANREACH',
            onBack: () {},
            onTransaction: (ref) => opened = ref,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 18:00 UTC on Nov 3 is already Nov 4 in Cambodia.
      expect(find.text('04 Nov 2026'), findsOneWidget);
      expect(find.text('03 Nov 2026'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('wallet-posting-KSR261104000128')),
          matching: find.text('−1,947 ៛'),
        ),
        findsOneWidget,
      );
      expect(find.text('+1,947 ៛'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('wallet-posting-KSR261103000130')),
        100,
      );
      expect(
        find.byKey(const ValueKey('wallet-posting-KSR261103000130')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('wallet-posting-KSR261103000130')),
          matching: find.text('−1,947 ៛'),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('wallet-posting-KSR261104000128')),
      );
      await tester.tap(
        find.byKey(const ValueKey('wallet-posting-KSR261104000128')),
      );
      expect(opened, 'KSR261104000128');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'receipt reveals real metadata and never invents an approval code',
    (tester) async {
      final rig = await DetailRig.create();
      addTearDown(rig.dispose);
      var closed = false;
      await tester.pumpWidget(
        detailsHarness(
          TransactionDetailScreen(
            accounts: rig.accounts,
            history: rig.history,
            reference: 'KSR261104000128',
            ownerName: 'SENG SOVANREACH',
            onBack: () => closed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('receipt-amount'))).data,
        '−3.00 USD',
      );
      expect(find.text('Unavailable'), findsOneWidget);
      expect(find.text('Lunch payment'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('receipt-view-more')));
      await tester.pumpAndSettle();
      expect(find.text('Lunch payment'), findsOneWidget);
      expect(find.text('1000000001'), findsOneWidget);
      expect(rig.history.detail!.status, 'SUCCESS');
      expect(find.text('Completed'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('receipt-view-more')),
      );
      await tester.tap(find.byKey(const ValueKey('receipt-view-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Close transaction details'));
      expect(closed, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'receipt download and share send actual PNGs through Android export',
    (tester) async {
      final rig = await DetailRig.create();
      addTearDown(rig.dispose);
      final methods = <String>[];
      const channel = MethodChannel('com.bank.customer_app/share');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        methods.add(call.method);
        final bytes = (call.arguments as Map)['png'] as List<int>;
        expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        expect((call.arguments as Map)['name'], contains('KSR261104000128'));
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        detailsHarness(
          TransactionDetailScreen(
            accounts: rig.accounts,
            history: rig.history,
            reference: 'KSR261104000128',
            ownerName: 'SENG SOVANREACH',
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final key in ['receipt-download', 'receipt-share']) {
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 180)),
        );
        await tester.pumpAndSettle();
      }
      expect(methods, ['saveImage', 'shareImage']);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'receipt error retry replaces stale data and disables export until fetched',
    (tester) async {
      final rig = await DetailRig.create();
      addTearDown(rig.dispose);
      rig.api.onDetail = (_, _) async =>
          throw const ApiFailure('OFFLINE', 'Offline fixture');
      await rig.history.openDetail('next-reference');
      final gate = Completer<RecentPosting>();
      rig.api.onDetail = (_, _) => gate.future;
      await tester.pumpWidget(
        detailsHarness(
          ListenableBuilder(
            listenable: rig.history,
            builder: (_, _) => TransactionDetailScreen(
              accounts: rig.accounts,
              history: rig.history,
              reference: 'next-reference',
              ownerName: 'Owner',
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Offline fixture'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('receipt-share')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Retry transaction details'));
      await tester.pump();
      expect(find.byKey(const ValueKey('receipt-amount')), findsNothing);
      gate.complete(detailPosting('USD', reference: 'next-reference'));
      await tester.pumpAndSettle();
      expect(find.text('next-reference'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('receipt-share')))
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
