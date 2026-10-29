import 'package:customer_app/app/banking_app.dart';
import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/accounts/creation_store.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:customer_app/features/transactions/transfer_models.dart';
import 'package:customer_app/features/transactions/transfer_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'accounts_test.dart' show FakeAccounts;
import 'transactions_test.dart' show FakeTransactions, funded, posting;
import 'support/fakes.dart';

void main() {
  late SessionController session;
  late FakeTransactions gateway;
  Future<void> mount(WidgetTester tester) async {
    session = SessionController(
      FakeGateway()..expiresInMs = 600000,
      MemorySessionVault(),
    );
    await session.initialize();
    await session.begin(
      email: 'qa@example.test',
      password: 'Password1!',
      register: false,
    );
    await session.verifyCode('123456');
    gateway = FakeTransactions();
    await tester.pumpWidget(
      BankingApp(
        session: session,
        config: AppConfig(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          environment: 'dev',
        ),
        accountGateway: FakeAccounts()..data = [funded(1)],
        creationStore: MemoryCreationStore(),
        transactionGateway: gateway,
        transferStore: MemoryTransferStore(),
      ),
    );
    await tester.pumpAndSettle();
  }

  tearDown(() => session.dispose());
  Future<void> tap(WidgetTester tester, String label) async {
    final finder = find.text(label).evaluate().isNotEmpty
        ? find.text(label).first
        : find.byTooltip(label).first;
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
  }

  Future<void> fill(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey('transfer-destination')),
      funded(2).number,
    );
    await tester.enterText(
      find.byKey(const ValueKey('transfer-amount')),
      '5.00',
    );
  }

  for (final size in [const Size(375, 667), const Size(667, 375)]) {
    testWidgets(
      'transfer review/result fits $size with 2x text, dark and reduced motion',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        await mount(tester);
        await tap(tester, 'Transfer');
        await fill(tester);
        await tap(tester, 'Review transfer');
        expect(gateway.requests, isEmpty);
        expect(find.text(funded(2).number), findsOneWidget);
        await tap(tester, 'Confirm and send');
        expect(find.text('Transfer confirmed'), findsOneWidget);
        await tap(tester, 'Done — return to transfer entry');
        expect(gateway.committed.length, 1);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'unknown transfer retains original key and logout removes private contents',
    (tester) async {
      await mount(tester);
      gateway.loseResponse = true;
      await tap(tester, 'Transfer');
      await fill(tester);
      await tap(tester, 'Review transfer');
      await tap(tester, 'Confirm and send');
      expect(find.text('Transfer outcome unknown'), findsOneWidget);
      final key = gateway.requests.single.key;
      await tap(tester, 'Retry this exact transfer');
      expect(gateway.requests.last.key, key);
      expect(gateway.committed.length, 1);
      await tap(tester, 'Profile');
      await tap(tester, 'Sign out');
      expect(find.text(funded(2).number), findsNothing);
      expect(find.textContaining('TXN-'), findsNothing);
      expect(find.text('Continue with Email'), findsOneWidget);
    },
  );
  testWidgets('history opens details and stays public after logout', (
    tester,
  ) async {
    await mount(tester);
    final record = SavedTransfer.confirmed(
      TransferDraft.validate(funded(1), funded(2).number, '5', 'memo'),
    );
    gateway.historyItems = [posting(record)];
    gateway.committed[record.key] = posting(record);
    await tap(tester, 'All transactions');
    await tap(tester, 'Refresh recent activity');
    await tap(tester, 'View transaction details');
    expect(find.text('Transaction details'), findsOneWidget);
    expect(find.text('Remark: memo'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Transaction history'), findsOneWidget);
    await tap(tester, 'Profile');
    await tap(tester, 'Sign out');
    expect(find.textContaining('TXN-'), findsNothing);
  });
  testWidgets(
    'transfer form and confirmation have accessible Android touch targets',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await mount(tester);
      await tap(tester, 'Transfer');
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await fill(tester);
      await tap(tester, 'Review transfer');
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
    },
  );
}
