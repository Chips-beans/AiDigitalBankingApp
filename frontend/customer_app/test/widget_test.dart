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

  testWidgets('register, wrong code, success, sign-out and back guard', (
    tester,
  ) async {
    await mount(tester);
    await tap(tester, find.text('Create a profile'));
    await tester.enterText(find.byKey(const ValueKey('username')), 'customer');
    await tester.enterText(
      find.byKey(const ValueKey('email')),
      'customer@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('password')),
      'Password123!',
    );
    await tester.enterText(
      find.byKey(const ValueKey('confirmPassword')),
      'Password123!',
    );
    await tap(tester, find.text('Send email code'));
    expect(find.text('Check your email'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('otpCode')), '000000');
    await tap(tester, find.text('Create profile'));
    expect(find.textContaining('did not match'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('otpCode')), '123456');
    await tap(tester, find.text('Create profile'));
    expect(find.text('You’re signed in.'), findsOneWidget);
    await tap(tester, find.text('Sign out'));
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('You’re signed in.'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('You’re signed in.'), findsNothing);
  });
  testWidgets('form validation blocks empty input and password mismatch', (
    tester,
  ) async {
    await mount(tester);
    await tap(tester, find.text('Create a profile'));
    await tap(tester, find.text('Send email code'));
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(session.screen, AuthScreen.register);
    await tester.enterText(find.byKey(const ValueKey('username')), 'customer');
    await tester.enterText(
      find.byKey(const ValueKey('email')),
      'customer@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('password')),
      'Password123!',
    );
    await tester.enterText(
      find.byKey(const ValueKey('confirmPassword')),
      'different',
    );
    await tap(tester, find.text('Send email code'));
    expect(find.text('Passwords must match.'), findsOneWidget);
  });
  testWidgets('back from OTP discards draft and stays on login form', (
    tester,
  ) async {
    await mount(tester);
    await tap(tester, find.text('Sign in'));
    await tester.enterText(
      find.byKey(const ValueKey('email')),
      'customer@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('password')),
      'Password123!',
    );
    await tap(tester, find.text('Send email code'));
    await tap(tester, find.text('Change your details'));
    expect(session.screen, AuthScreen.login);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(session.otpEmail, '');
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('password')))
          .controller!
          .text,
      '',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(session.screen, AuthScreen.welcome);
  });
  for (final size in [const Size(375, 667), const Size(667, 375)]) {
    testWidgets(
      'all screens fit $size with 2x text, dark mode and reduced motion',
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
        await tap(tester, find.text('Create a profile'));
        expect(tester.takeException(), null);
        session.back();
        session.openForm(register: false);
        await session.begin(
          email: 'x@example.test',
          password: 'Password1!',
          register: false,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), null);
        await session.verifyCode('123456');
        await tester.pumpAndSettle();
        expect(tester.takeException(), null);
        expect(find.text('Your profile'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'visible controls meet Android target size and semantics labels',
    (tester) async {
      final handle = tester.ensureSemantics();
      await mount(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tap(tester, find.text('Create a profile'));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    },
  );
}
