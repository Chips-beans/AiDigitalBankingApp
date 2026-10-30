import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/features/accounts/accounts_controller.dart';
import 'package:customer_app/features/accounts/creation_store.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:customer_app/features/transactions/presentation/kesor_transfer_screen.dart';
import 'package:customer_app/features/transactions/recipient_favorites.dart';
import 'package:customer_app/features/transactions/transfer_controller.dart';
import 'package:customer_app/features/transactions/transfer_store.dart';
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
  late RecipientFavoritesStore favorites;
  late AppPreferences prefs;
  Future<void> mount(WidgetTester tester, {bool enabled = true}) async {
    session = await signedSession();
    accounts = AccountsController(
      session,
      FakeAccounts()
        ..data = [
          funded(1),
          funded(3, currency: 'KHR', balance: '100000'),
          funded(4, status: 'FROZEN'),
        ],
      MemoryCreationStore(),
    );
    await accounts.initialize();
    gateway = FakeTransactions();
    transfers = TransferController(session, gateway, MemoryTransferStore());
    await transfers.initialize();
    favorites = RecipientFavoritesStore();
    prefs = AppPreferences();
    await tester.pumpWidget(
      AppPreferencesScope(
        preferences: prefs,
        child: MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: KesorTransferScreen(
            controller: transfers,
            accounts: accounts,
            enabled: enabled,
            onBack: () {},
            favorites: favorites,
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

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
  }

  Future<void> fill(WidgetTester tester, {String amount = '5.00'}) async {
    await tester.enterText(
      find.byKey(const ValueKey('transfer-destination')),
      funded(2).number,
    );
    await tester.enterText(
      find.byKey(const ValueKey('transfer-amount')),
      amount,
    );
  }

  final continueButton = find.byKey(const ValueKey('transfer-continue'));
  final walletPicker = find.byKey(const ValueKey('transfer-wallet-picker'));
  testWidgets(
    'invalid fields send nothing; editing a review retains entered values',
    (tester) async {
      await mount(tester);
      await tap(tester, continueButton);
      expect(find.text('Enter 10–20 digits.'), findsOneWidget);
      expect(find.text('Enter an amount.'), findsOneWidget);
      expect(gateway.requests, isEmpty);
      await fill(tester);
      await tap(tester, continueButton);
      expect(transfers.review, isNotNull);
      expect(gateway.requests, isEmpty);
      await tap(tester, find.text('Edit transfer'));
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('transfer-destination')),
            )
            .controller!
            .text,
        funded(2).number,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('transfer-amount')),
            )
            .controller!
            .text,
        '5.00',
      );
    },
  );
  testWidgets(
    'wallet selection uses live balances and enforces whole KHR amounts',
    (tester) async {
      await mount(tester);
      await tap(tester, walletPicker);
      final frozen = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'FROZEN'),
      );
      expect(frozen.enabled, false);
      await tap(tester, find.text('Khmer Riel Wallet'));
      expect(find.text('KHR 100,000'), findsOneWidget);
      await fill(tester, amount: '1.2');
      await tap(tester, continueButton);
      expect(transfers.review, null);
      expect(transfers.error, isNotNull);
      await fill(tester, amount: '10000');
      await tap(tester, continueButton);
      expect(transfers.review!.source, funded(3).number);
      expect(transfers.review!.amount.currency, 'KHR');
      expect(gateway.requests, isEmpty);
    },
  );
  testWidgets(
    'favorite is saved only after a confirmed result, including explicit timeout retry',
    (tester) async {
      await mount(tester);
      gateway.loseResponse = true;
      await fill(tester);
      await tap(tester, find.byKey(const ValueKey('transfer-favorite-toggle')));
      await tap(tester, continueButton);
      expect(await favorites.read(1), isEmpty);
      await tap(tester, find.text('Confirm and send'));
      expect(find.text('Transfer outcome unknown'), findsOneWidget);
      expect(await favorites.read(1), isEmpty);
      final key = gateway.requests.single.key;
      await tap(tester, find.text('Retry this exact transfer'));
      expect(gateway.requests.last.key, key);
      expect((await favorites.read(1)).single.number, funded(2).number);
      expect(gateway.committed, hasLength(1));
    },
  );
  testWidgets(
    'saved recipient is currency-filtered and fills the form without submitting',
    (tester) async {
      await mount(tester);
      await favorites.add(1, FavoriteRecipient(funded(2).number, 'USD'));
      await favorites.add(1, FavoriteRecipient(funded(5).number, 'KHR'));
      await tap(tester, find.bySemanticsLabel('Saved recipients'));
      expect(find.text(funded(5).number), findsNothing);
      await tap(tester, find.widgetWithText(ListTile, funded(2).number));
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('transfer-destination')),
            )
            .controller!
            .text,
        funded(2).number,
      );
      expect(transfers.review, null);
      expect(gateway.requests, isEmpty);
    },
  );
  testWidgets(
    'wallet sheet closes and personal fields clear when the owner logs out',
    (tester) async {
      await mount(tester);
      await fill(tester);
      await tap(tester, walletPicker);
      await session.signOut();
      await tester.pumpAndSettle();
      expect(find.text('Khmer Riel Wallet'), findsNothing);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('transfer-destination')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(gateway.requests, isEmpty);
      expect(tester.takeException(), null);
    },
  );
  testWidgets('browser or demo preview keeps transfer submission disabled', (
    tester,
  ) async {
    await mount(tester, enabled: false);
    await fill(tester);
    expect(tester.widget<FilledButton>(continueButton).onPressed, null);
    expect(transfers.review, null);
    expect(gateway.requests, isEmpty);
  });
}
