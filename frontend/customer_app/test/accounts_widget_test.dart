import 'package:customer_app/app/banking_app.dart';
import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/accounts/creation_store.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'accounts_test.dart' show FakeAccounts, account;
import 'support/fakes.dart';

void main() {
  for (final size in [
    const Size(375, 667),
    const Size(667, 375),
    const Size(1024, 768),
  ]) {
    testWidgets(
      'populated accounts, form, details, tabs at $size with large text',
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
        final auth = FakeGateway()..expiresInMs = 600000;
        final session = SessionController(auth, MemorySessionVault());
        addTearDown(session.dispose);
        await session.initialize();
        await session.begin(
          email: 'customer@example.test',
          password: 'Password1!',
          register: false,
        );
        await session.verifyCode('123456');
        final gateway = FakeAccounts()
          ..data = [
            account(1, status: 'FROZEN'),
            account(2, currency: 'KHR', status: 'CLOSED'),
          ];
        await tester.pumpWidget(
          BankingApp(
            session: session,
            config: AppConfig(
              apiBaseUrl: 'http://localhost:8080/api/v1',
              environment: 'dev',
            ),
            accountGateway: gateway,
            creationStore: MemoryCreationStore(),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), null);
        Future<void> tap(String label) async {
          final finder = find.text(label).evaluate().isNotEmpty
              ? find.text(label)
              : find.byTooltip(label);
          await tester.ensureVisible(finder);
          await tester.tap(finder);
          await tester.pumpAndSettle();
          expect(tester.takeException(), null);
        }

        await tap('View accounts');
        expect(find.text('Status: FROZEN'), findsOneWidget);
        await tap('View account details');
        expect(find.text('Currency: USD'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tap('Open account');
        expect(find.text('Opening balance: USD 0.00'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tap('Home');
        await tap('All transactions');
        expect(find.text('No activity yet for this account.'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Balance'), findsOneWidget);
        await tap('View accounts');
        await tap('Profile');
        expect(find.text('customer@example.test'), findsOneWidget);
        await tap('Sign out');
        expect(find.text('Continue with Email'), findsOneWidget);
        expect(find.textContaining('1000000001'), findsNothing);
      },
    );
  }
  testWidgets(
    'account opening is explicit and all tab controls have labels and touch targets',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final auth = FakeGateway()..expiresInMs = 600000;
      final session = SessionController(auth, MemorySessionVault());
      addTearDown(session.dispose);
      await session.initialize();
      await session.begin(
        email: 'customer@example.test',
        password: 'Password1!',
        register: false,
      );
      await session.verifyCode('123456');
      final gateway = FakeAccounts();
      await tester.pumpWidget(
        BankingApp(
          session: session,
          config: AppConfig(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            environment: 'dev',
          ),
          accountGateway: gateway,
          creationStore: MemoryCreationStore(),
        ),
      );
      await tester.pumpAndSettle();
      expect(gateway.opens, 0);
      await tester.tap(find.byTooltip('View accounts'));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.tap(find.text('Open account'));
      await tester.pumpAndSettle();
      expect(gateway.opens, 0);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.tap(find.text('Confirm open account'));
      await tester.pumpAndSettle();
      expect(gateway.opens, 1);
      expect(find.text('USD 0.00'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
    },
  );
}
