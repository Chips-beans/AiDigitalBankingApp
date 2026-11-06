import 'dart:async';
import 'dart:convert';

import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/core/network/api_client.dart';
import 'package:customer_app/features/accounts/account_gateway.dart';
import 'package:customer_app/features/accounts/accounts_controller.dart';
import 'package:customer_app/features/accounts/creation_store.dart';
import 'package:customer_app/features/accounts/presentation/accounts_shell.dart';
import 'package:customer_app/features/accounts/presentation/wallet_accounts_screen.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:customer_app/features/home/home_unlock_target.dart';
import 'package:customer_app/features/transactions/transfer_store.dart';
import 'package:customer_app/features/transactions/transaction_gateway.dart';
import 'package:customer_app/shared/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'accounts_test.dart' show FakeAccounts;
import 'qr_pairs_test.dart' show signedSession, accountJson;
import 'transactions_test.dart' show FakeTransactions, funded;
import 'wallet_details_design_test.dart' show detailsHarness;

BankAccount merchantWallet(
  int id, {
  String currency = 'USD',
  String balance = '0',
}) => BankAccount(
  id: id,
  number: '${2000000000 + id}',
  type: 'CHECKING',
  balance: Money.parse(balance, currency),
  status: 'ACTIVE',
  createdAt: DateTime.utc(2026),
  accountCategory: 'MERCHANT',
  merchantId: 42,
);

class FakeMerchantAccounts extends FakeAccounts
    implements MerchantWalletSource {
  List<BankAccount> merchants = [];
  ApiFailure? merchantFailure;
  Completer<List<BankAccount>>? merchantGate;
  final merchantPages = <int>[];
  final details = <String>[];
  @override
  Future<List<BankAccount>> merchantList(String token, int page) async {
    merchantPages.add(page);
    if (merchantGate != null) return merchantGate!.future;
    if (merchantFailure != null) throw merchantFailure!;
    return merchants.skip(page * 20).take(20).toList();
  }

  @override
  Future<BankAccount> detail(String token, String number) async {
    details.add(number);
    return [...data, ...merchants].firstWhere((a) => a.number == number);
  }
}

class MerchantWalletRig {
  MerchantWalletRig(this.session, this.gateway, this.personal, this.merchant);
  final SessionController session;
  final FakeMerchantAccounts gateway;
  final AccountsController personal, merchant;
  static Future<MerchantWalletRig> create({bool linked = true}) async {
    final session = await signedSession();
    final gateway = FakeMerchantAccounts()
      ..data = [funded(1), funded(2, currency: 'KHR', balance: '25000')]
      ..merchants = linked
          ? [
              merchantWallet(3, balance: '12.34'),
              merchantWallet(4, currency: 'KHR'),
            ]
          : [];
    final personal = AccountsController(
      session,
      gateway,
      MemoryCreationStore(),
    );
    final merchant = AccountsController(
      session,
      MerchantWalletGateway(gateway),
      MemoryCreationStore(),
    );
    await personal.initialize();
    return MerchantWalletRig(session, gateway, personal, merchant);
  }

  Widget screen({bool visible = true}) => WalletAccountsScreen(
    model: personal,
    merchantModel: merchant,
    greetingName: 'Sok Dara',
    onBack: () {},
    onProfile: () {},
    onTransfer: () {},
    onMyQr: () {},
    onOpenAccounts: () {},
    onDetails: () {},
    onActivity: () {},
    onMerchantDetails: () {},
    bottomBar: const SizedBox(),
    balanceVisible: visible,
    onRefresh: () async =>
        Future.wait([personal.refresh(), merchant.refresh()]),
  );
  void dispose() {
    personal.dispose();
    merchant.dispose();
    session.dispose();
  }
}

void main() {
  test(
    'merchant API uses owner-scoped category, paging and exact money',
    () async {
      final client = ApiClient(
        AppConfig(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          environment: 'dev',
        ),
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/accounts/me');
          expect(request.url.queryParameters, {
            'category': 'MERCHANT',
            'page': '2',
            'size': '20',
          });
          expect(request.headers['authorization'], 'Bearer fixture-token');
          return http.Response(
            jsonEncode({
              'success': true,
              'data': [
                {
                  ...accountJson('USD'),
                  'accountCategory': 'MERCHANT',
                  'merchantId': 42,
                  'balance': '9999999999999.99',
                },
              ],
            }),
            200,
          );
        }),
      );
      final result = await MerchantWalletGateway(HttpAccountGateway(client))
          .list('fixture-token', 2);
      expect(result.single.merchantId, 42);
      expect(result.single.balance.decimal, '9999999999999.99');
      expect(BankAccount.fromJson(accountJson('USD')).isMerchant, false);
      for (final changes in [
        {'accountCategory': 'OTHER'},
        {'accountCategory': 'MERCHANT'},
        {'accountCategory': 'MERCHANT', 'merchantId': -1},
      ]) {
        expect(
          () => BankAccount.fromJson({...accountJson('USD'), ...changes}),
          throwsA(isA<ApiFailure>()),
        );
      }
    },
  );

  test(
    'merchant adapter rejects personal data and all account opening',
    () async {
      final api = FakeMerchantAccounts()..merchants = [funded(1)];
      final adapter = MerchantWalletGateway(api);
      await expectLater(adapter.list('token', 0), throwsA(isA<ApiFailure>()));
      api.data = [funded(1)];
      await expectLater(
        adapter.detail('token', funded(1).number),
        throwsA(isA<ApiFailure>()),
      );
      await expectLater(
        adapter.open('token', 'CHECKING', 'USD'),
        throwsA(isA<ApiFailure>()),
      );
      expect(api.opens, 0);
      expect(
        await MerchantWalletGateway(FakeAccounts()).list('token', 0),
        isEmpty,
      );
    },
  );

  test(
    'merchant pagination and selection never alter personal controllers',
    () async {
      final rig = await MerchantWalletRig.create();
      addTearDown(rig.dispose);
      rig.gateway.merchants = List.generate(21, (i) => merchantWallet(i + 10));
      await rig.merchant.refresh();
      expect(rig.merchant.accounts.length, 20);
      expect(rig.merchant.hasMore, true);
      await rig.merchant.loadMore();
      expect(rig.gateway.merchantPages, [0, 1]);
      expect(rig.merchant.accounts.length, 21);
      await rig.merchant.select(rig.merchant.accounts.last);
      expect(rig.personal.accounts.every((a) => !a.isMerchant), true);
      expect(rig.personal.selected!.number, funded(1).number);
      expect(await rig.merchant.open('CHECKING', 'USD'), false);
      rig.gateway.merchants = [];
      await rig.merchant.refresh();
      expect(rig.merchant.accounts, isEmpty);
      expect(rig.merchant.selected, null);
    },
  );

  test('failed refresh retains balances; retry updates; sign-out discards late data', () async {
    final rig = await MerchantWalletRig.create();
    addTearDown(rig.dispose);
    await rig.merchant.refresh();
    rig.gateway.merchantFailure = const ApiFailure('NETWORK', 'Offline');
    await rig.merchant.refresh();
    expect(rig.merchant.listError, isNotNull);
    expect(rig.merchant.accounts.first.balance.decimal, '12.34');
    rig.gateway.merchantFailure = null;
    rig.gateway.merchants = [merchantWallet(3, balance: '45.67')];
    await rig.merchant.refresh();
    expect(rig.merchant.listError, null);
    expect(rig.merchant.accounts.single.balance.decimal, '45.67');
    final gate = rig.gateway.merchantGate = Completer<List<BankAccount>>();
    final request = rig.merchant.refresh();
    await Future<void>.delayed(Duration.zero);
    await rig.session.signOut();
    expect(rig.merchant.accounts, isEmpty);
    gate.complete([merchantWallet(3)]);
    await request;
    expect(rig.merchant.accounts, isEmpty);
    expect(rig.merchant.selected, null);
  });

  test('newer merchant refresh wins over an older response', () async {
    final rig = await MerchantWalletRig.create();
    addTearDown(rig.dispose);
    final gate = rig.gateway.merchantGate = Completer<List<BankAccount>>();
    final old = rig.merchant.refresh();
    await Future<void>.delayed(Duration.zero);
    rig.gateway.merchantGate = null;
    await rig.merchant.refresh();
    gate.complete([]);
    await old;
    expect(rig.merchant.accounts.length, 2);
  });

  testWidgets(
    'unregistered shop hides cards; screen reentry discovers registration',
    (tester) async {
      final rig = await MerchantWalletRig.create(linked: false);
      addTearDown(rig.dispose);
      await tester.pumpWidget(detailsHarness(rig.screen()));
      await tester.pumpAndSettle();
      expect(find.text('2 wallets'), findsOneWidget);
      expect(find.textContaining('Merchant'), findsNothing);
      expect(
        find.byKey(const ValueKey('merchant-wallet-unavailable')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      rig.gateway.merchants = [
        merchantWallet(3),
        merchantWallet(4, currency: 'KHR'),
      ];
      await tester.pumpWidget(detailsHarness(rig.screen()));
      await tester.pumpAndSettle();
      expect(find.text('4 wallets'), findsOneWidget);
      expect(find.text('Merchant KHR Wallet'), findsOneWidget);
      expect(find.text('Merchant USD Wallet'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Merchant KHR Wallet')).dy,
        lessThan(tester.getTopLeft(find.text('Merchant USD Wallet')).dy),
      );
      expect(find.text('Not configured'), findsNothing);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'loading, isolated retry, stale balances, copy and masking work',
    (tester) async {
      tester.view.physicalSize = const Size(480, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rig = await MerchantWalletRig.create();
      addTearDown(rig.dispose);
      final gate = rig.gateway.merchantGate = Completer<List<BankAccount>>();
      await tester.pumpWidget(detailsHarness(rig.screen()));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('merchant-wallet-loading')),
        findsOneWidget,
      );
      gate.complete(rig.gateway.merchants);
      rig.gateway.merchantGate = null;
      await tester.pumpAndSettle();
      expect(find.text(r'$12.34'), findsOneWidget);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final card = find.byKey(
        ValueKey('wallet-tile-${merchantWallet(3).number}'),
      );
      await tester.tap(
        find.descendant(of: card, matching: find.byType(IconButton)),
      );
      await tester.pumpAndSettle();
      expect(copied, merchantWallet(3).number);
      rig.gateway.merchantFailure = const ApiFailure('NETWORK', 'Offline');
      await rig.merchant.refresh();
      await tester.pumpAndSettle();
      expect(find.textContaining('out of date'), findsOneWidget);
      expect(find.text(r'$12.34'), findsOneWidget);
      expect(find.textContaining('Retry accounts'), findsNothing);
      rig.gateway.merchantFailure = null;
      rig.gateway.merchants = [merchantWallet(3, balance: '20.00')];
      await tester.tap(find.text('Retry merchant wallets'));
      await tester.pumpAndSettle();
      expect(find.text(r'$20.00'), findsOneWidget);
      await tester.pumpWidget(detailsHarness(rig.screen(visible: false)));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.byKey(
                ValueKey('wallet-balance-${merchantWallet(3).number}'),
              ),
            )
            .data,
        '••••',
      );
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final currency in ['KHR', 'USD']) {
    testWidgets(
      '$currency merchant detail and receipt return to Wallets without changing personal source',
      (tester) async {
        tester.view.physicalSize = const Size(480, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final session = await signedSession();
        addTearDown(session.dispose);
        final business = merchantWallet(3, currency: currency, balance: '100');
        final api = FakeMerchantAccounts()
          ..data = [funded(1), funded(2, currency: 'KHR', balance: '25000')]
          ..merchants = [business];
        final tx = RecentPosting(
          reference: 'MERCHANT-RECEIPT',
          source: funded(1).number,
          destination: business.number,
          amount: Money.parse('5', currency),
          fee: Money.parse('0', currency),
          type: 'TRANSFER',
          status: 'SUCCESS',
          createdAt: DateTime.utc(2026, 11, 6),
          sourceName: 'Dara',
          operation: 'MERCHANT_QR_PAYMENT',
        );
        final requests = <String>[];
        final transactions = FakeTransactions()
          ..onHistory = (number, page) async {
            return PostingPage(
              number == business.number ? [tx] : [],
              page,
              true,
              number == business.number ? 1 : 0,
            );
          }
          ..onDetail = (number, ref) async {
            requests.add(number);
            return tx;
          };
        await tester.pumpWidget(
          detailsHarness(
            AccountsShell(
              session: session,
              gateway: api,
              store: MemoryCreationStore(),
              transactions: transactions,
              transferStore: MemoryTransferStore(),
              transfersEnabled: true,
              designPreview: true,
              initialTarget: const HomeUnlockTarget('accounts'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey('wallet-tile-${business.number}')),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Merchant $currency Wallet'),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Account options'));
        await tester.pumpAndSettle();
        expect(find.text('My QR'), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Dara'));
        await tester.pumpAndSettle();
        expect(requests, [business.number]);
        expect(find.byKey(const ValueKey('receipt-amount')), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Wallet details'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('3 wallets'), findsOneWidget);
        // The personal history action must still resolve the original USD wallet.
        await tester.tap(find.text('View recent activity'));
        await tester.pumpAndSettle();
        expect(find.textContaining('US Dollar Wallet'), findsOneWidget);
        expect(find.textContaining('Merchant $currency Wallet'), findsNothing);
        expect(api.opens, 0);
        expect(transactions.requests, isEmpty);
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
