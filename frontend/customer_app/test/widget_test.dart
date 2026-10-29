import 'package:customer_app/app/banking_app.dart';
import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/auth/data/auth_gateway.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final config = AppConfig(
    apiBaseUrl: 'http://localhost:8080/api/v1',
    environment: 'dev',
    mode: 'demo',
  );
  late SessionController session;
  tearDown(() => session.dispose());
  Future<void> mount(WidgetTester tester) async {
    session = SessionController(DemoAuthGateway(), MemorySessionVault());
    await session.initialize();
    await tester.pumpWidget(BankingApp(session: session, config: config));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> email(WidgetTester tester) async {
    await tap(tester, find.text('Continue with Email'));
    await tester.enterText(
      find.byKey(const ValueKey('email')),
      'customer@example.test',
    );
    await tap(tester, find.text('Send verification code'));
  }

  Future<void> code(WidgetTester tester, String code) async {
    await tester.enterText(find.byKey(const ValueKey('otpCode')), code);
    await tap(tester, find.text('Verify and continue'));
  }

  Future<void> complete(WidgetTester tester) async {
    await tester.enterText(find.byKey(const ValueKey('firstName')), 'Dara');
    await tester.enterText(find.byKey(const ValueKey('lastName')), 'Sok');
    await tap(tester, find.text('Continue to Kesor'));
  }

  testWidgets('one welcome screen offers only continuation options', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('Continue with Telegram'), findsOneWidget);
    expect(find.text('Continue with Email'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
    expect(find.text('Create a profile'), findsNothing);
  });
  testWidgets('new email, wrong code, onboarding, home, and sign-out', (
    tester,
  ) async {
    await mount(tester);
    await email(tester);
    await code(tester, '000000');
    expect(find.textContaining('did not match'), findsOneWidget);
    await code(tester, '123456');
    expect(find.text('A little about you'), findsOneWidget);
    expect(find.byTooltip('Home'), findsNothing);
    expect(session.identity!.profileComplete, false);
    await complete(tester);
    expect(find.byTooltip('Home'), findsOneWidget);
    await tap(tester, find.byTooltip('View accounts'));
    await tap(tester, find.byTooltip('Profile'));
    expect(find.text('Dara Sok'), findsOneWidget);
    await tap(tester, find.text('Sign out'));
    expect(find.text('Continue with Email'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('A little about you'), findsNothing);
  });
  testWidgets('returning email skips information form', (tester) async {
    await mount(tester);
    await email(tester);
    await code(tester, '123456');
    await complete(tester);
    await session.signOut();
    await tester.pumpAndSettle();
    await email(tester);
    await code(tester, '123456');
    expect(find.byTooltip('Home'), findsOneWidget);
    expect(find.text('A little about you'), findsNothing);
  });
  testWidgets('email and information fields validate without passwords', (
    tester,
  ) async {
    await mount(tester);
    await tap(tester, find.text('Continue with Email'));
    await tap(tester, find.text('Send verification code'));
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.byKey(const ValueKey('password')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('email')),
      'customer@example.test',
    );
    await tap(tester, find.text('Send verification code'));
    await code(tester, '123456');
    await tap(tester, find.text('Continue to Kesor'));
    expect(find.text('Enter your first name.'), findsOneWidget);
    expect(find.byTooltip('Home'), findsNothing);
  });
  testWidgets('back from code discards challenge and returns to email', (
    tester,
  ) async {
    await mount(tester);
    await email(tester);
    await tap(tester, find.text('Change your details'));
    expect(session.screen, AuthScreen.email);
    expect(session.otpEmail, '');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(session.screen, AuthScreen.welcome);
  });
  for (final size in [
    const Size(375, 667),
    const Size(667, 375),
    const Size(1024, 768),
  ]) {
    testWidgets(
      'continuation screens fit $size with large text and reduced motion',
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
        expect(tester.takeException(), null);
        await email(tester);
        expect(tester.takeException(), null);
        await code(tester, '123456');
        expect(tester.takeException(), null);
        await complete(tester);
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets('continuation controls meet target and label guidelines', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await mount(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await tap(tester, find.text('Continue with Email'));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
