import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/features/accounts/accounts_controller.dart';
import 'package:customer_app/features/accounts/creation_store.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:customer_app/features/qr/presentation/qr_transfer_screen.dart';
import 'package:customer_app/features/transactions/presentation/kesor_transfer_screen.dart';
import 'package:customer_app/features/transactions/recipient_favorites.dart';
import 'package:customer_app/features/transactions/transfer_controller.dart';
import 'package:customer_app/features/transactions/transfer_models.dart';
import 'package:customer_app/features/transactions/transfer_store.dart';
import 'package:customer_app/shared/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'accounts_test.dart' show FakeAccounts;
import 'qr_pairs_test.dart' show signedSession;
import 'transactions_test.dart' show FakeTransactions, funded;

void main() {
  late SessionController session;
  late AccountsController accounts;
  late TransferController transfers;
  late FakeTransactions gateway;
  late AppPreferences prefs;
  Future<void> mount(
    WidgetTester tester, {
    Money? fixed,
    bool shop = false,
    bool normal = false,
  }) async {
    tester.view.physicalSize = const Size(440, 957);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    session = await signedSession();
    accounts = AccountsController(
      session,
      FakeAccounts()
        ..data = [
          funded(1, balance: '168'),
          funded(3, currency: 'KHR', balance: '100000'),
        ],
      MemoryCreationStore(),
    );
    await accounts.initialize();
    gateway = FakeTransactions();
    transfers = TransferController(session, gateway, MemoryTransferStore());
    await transfers.initialize();
    prefs = AppPreferences();
    await tester.pumpWidget(
      AppPreferencesScope(
        preferences: prefs,
        child: MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: KesorTransferScreen(
            controller: transfers,
            accounts: accounts,
            enabled: true,
            onBack: () {},
            favorites: RecipientFavoritesStore(),
            prefill: normal
                ? null
                : TransferPrefill(
                    funded(2).number,
                    name: 'Sok Sophea',
                    qrString: 'verified-qr',
                    fixedAmount: fixed,
                    shop: shop
                        ? const ShopPayee(
                            merchantId: 'MCH-ABC12345',
                            storeName: 'Kesor Coffee',
                            currency: 'USD',
                            hasLogo: false,
                          )
                        : null,
                  ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      transfers.dispose();
      accounts.dispose();
      session.dispose();
      prefs.dispose();
    });
  }

  Future<void> key(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey('qr-key-$key')));
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester) =>
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('qr-transfer-continue')),
          )
          .onPressed !=
      null;
  String amount(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('qr-transfer-amount')))
      .data!;

  testWidgets(
    'QR is separate, destination immutable, zero disabled and precision exact',
    (tester) async {
      await mount(tester);
      expect(find.byType(QrTransferScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('transfer-destination')), findsNothing);
      expect(find.byType(Scrollable), findsNothing);
      expect(enabled(tester), false);
      for (final digit in ['1', '.', '2', '3', '4', '.']) {
        await key(tester, digit);
      }
      expect(amount(tester), '1.23');
      expect(enabled(tester), true);
      await key(tester, 'backspace');
      expect(amount(tester), '1.2');
      await tester.tap(find.byKey(const ValueKey('qr-transfer-continue')));
      await tester.pumpAndSettle();
      expect(transfers.review!.qrString, 'verified-qr');
      expect(transfers.review!.amount.decimal, '1.20');
      expect(transfers.review!.destinationName, 'Sok Sophea');
      expect(gateway.requests, isEmpty);
      await tester.tap(find.byKey(const ValueKey('transfer-edit')));
      await tester.pumpAndSettle();
      expect(find.byType(QrTransferScreen), findsOneWidget);
      expect(amount(tester), '1.2');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'currency selects wallet, clears static debit and KHR rejects decimals',
    (tester) async {
      await mount(tester);
      await key(tester, '5');
      await tester.tap(find.byKey(const ValueKey('qr-currency-KHR')));
      await tester.pumpAndSettle();
      expect(accounts.selected!.currency, 'KHR');
      expect(amount(tester), '0');
      for (final digit in ['2', '.', '5']) {
        await key(tester, digit);
      }
      expect(amount(tester), '25');
      await tester.tap(find.byKey(const ValueKey('qr-transfer-continue')));
      await tester.pumpAndSettle();
      expect(transfers.review!.amount.currency, 'KHR');
      expect(transfers.review!.amount.decimal, '25');
      expect(gateway.requests, isEmpty);
    },
  );

  testWidgets(
    'insufficient funds disables transfer and deletion restores validity',
    (tester) async {
      await mount(tester);
      for (final digit in ['9', '9', '9']) {
        await key(tester, digit);
      }
      expect(enabled(tester), false);
      await key(tester, 'backspace');
      expect(enabled(tester), true);
    },
  );

  testWidgets(
    'fixed requests cannot edit and use exact debit after wallet change',
    (tester) async {
      await mount(tester, fixed: Money.parse('2.50', 'USD'));
      expect(amount(tester), '2.50');
      await key(tester, '9');
      await key(tester, 'backspace');
      expect(amount(tester), '2.50');
      await tester.tap(find.byKey(const ValueKey('qr-currency-KHR')));
      await tester.pumpAndSettle();
      expect(amount(tester), '10000');
      await tester.tap(find.byKey(const ValueKey('qr-transfer-continue')));
      await tester.pumpAndSettle();
      expect(transfers.review!.qrFixed, true);
      expect(transfers.review!.qrPayload.containsKey('amount'), false);
      expect(transfers.review!.amount.decimal, '10000');
    },
  );

  testWidgets(
    'inexact fixed conversion blocked until matching wallet selected',
    (tester) async {
      await mount(tester, fixed: Money.parse('10001', 'KHR'));
      expect(enabled(tester), false);
      await tester.tap(find.byKey(const ValueKey('qr-currency-KHR')));
      await tester.pumpAndSettle();
      expect(amount(tester), '10001');
      expect(enabled(tester), true);
    },
  );

  testWidgets('verified merchant name and badge retained', (tester) async {
    await mount(tester, shop: true);
    expect(find.text('Kesor Coffee'), findsOneWidget);
    expect(find.text('Verified Kesor shop'), findsOneWidget);
    await key(tester, '5');
    await tester.tap(find.byKey(const ValueKey('qr-transfer-continue')));
    await tester.pumpAndSettle();
    expect(transfers.review!.destinationName, 'Kesor Coffee');
  });

  testWidgets('remark dialog preserves exact text and does not submit', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('qr-remark')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('qr-remark-editor')),
      'Lunch',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Lunch'), findsOneWidget);
    expect(gateway.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('normal entry keeps the existing transfer form', (tester) async {
    await mount(tester, normal: true);
    expect(find.byType(QrTransferScreen), findsNothing);
    expect(find.byKey(const ValueKey('transfer-destination')), findsOneWidget);
  });
}
