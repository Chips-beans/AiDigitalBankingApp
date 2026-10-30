import 'dart:async';

import 'package:customer_app/app/banking_app.dart';
import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/core/network/api_client.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/auth/data/app_pin_gateway.dart';
import 'package:customer_app/features/auth/data/auth_gateway.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class CountingAuth extends DemoAuthGateway {
  int refreshes = 0;
  @override
  Future<TokenPair> refresh(String token) {
    refreshes++;
    return super.refresh(token);
  }
}

class ControlledPinGateway extends DemoAppPinGateway {
  ControlledPinGateway(super.auth);
  int setups = 0, unlocks = 0;
  Completer<void>? unlockGate;
  @override
  Future<TokenPair> setup(
    String ticket,
    String pin,
    String confirmPin, {
    required bool reset,
  }) {
    setups++;
    return super.setup(ticket, pin, confirmPin, reset: reset);
  }

  @override
  Future<TokenPair> unlock(String ticket, String pin) async {
    unlocks++;
    await unlockGate?.future;
    return super.unlock(ticket, pin);
  }
}

void main() {
  late CountingAuth auth;
  late ControlledPinGateway pins;
  late MemorySessionVault vault;
  late SessionController session;
  setUp(() async {
    auth = CountingAuth();
    pins = ControlledPinGateway(auth);
    vault = MemorySessionVault();
    session = SessionController(auth, vault, pinGateway: pins);
    await session.initialize();
  });
  tearDown(() => session.dispose());
  Future<void> email([String value = 'pin@example.test']) async {
    session.openEmail();
    await session.beginEmail(value);
    expect(await session.verifyCode('123456'), isTrue);
  }

  Future<void> onboard() async {
    await email();
    await session.completeInformation('Dara', 'Sok');
  }

  Future<void> setup() async {
    await onboard();
    await session.submitPin('0427');
    await session.submitPin('0427');
  }

  test(
    'new profile must create and confirm PIN before any banking access',
    () async {
      await onboard();
      expect(session.phase, SessionPhase.pinLocked);
      expect(session.pinStage, PinStage.create);
      expect(vault.refreshToken, startsWith('kesor-pin-v1:'));
      expect(vault.refreshToken, isNot(contains('demo-only:')));
      await expectLater(
        session.authorizedRead((token) async => 'private'),
        throwsA(
          isA<ApiFailure>().having((e) => e.code, 'code', 'PIN_REQUIRED'),
        ),
      );
      await session.submitPin('0427');
      expect(session.pinStage, PinStage.confirm);
      expect(pins.setups, 0);
      expect(await session.submitPin('0428'), isFalse);
      expect(pins.setups, 0);
      expect(session.failure?.code, 'PIN_CONFIRMATION_MISMATCH');
      expect(await session.submitPin('0427'), isTrue);
      expect(session.phase, SessionPhase.signedIn);
      expect(vault.refreshToken, startsWith('kesor-pin-v1:'));
      expect(vault.refreshToken, isNot(contains('0427')));
    },
  );

  test(
    'process restart displays unlock without restoring banking tokens',
    () async {
      await setup();
      final previous = session;
      final refreshes = auth.refreshes;
      session = SessionController(auth, vault, pinGateway: pins);
      previous.dispose();
      await session.initialize();
      expect(session.phase, SessionPhase.pinLocked);
      expect(session.pinStage, PinStage.unlock);
      expect(auth.refreshes, refreshes);
      var requested = false;
      await expectLater(
        session.authorizedRead((token) async {
          requested = true;
          return 1;
        }),
        throwsA(isA<ApiFailure>()),
      );
      expect(requested, isFalse);
      expect(await session.submitPin('0427'), isTrue);
      expect(session.phase, SessionPhase.signedIn);
    },
  );

  test('failed attempt budget survives reopen and correct PIN cannot bypass recovery lock', () async {
    await setup();
    session.lockApp();
    await Future<void>.delayed(Duration.zero);
    for (var i = 0; i < 5; i++) {
      expect(await session.submitPin('9999'), isFalse);
    }
    expect(session.pinChallenge!.recoveryRequired, isTrue);
    expect(session.pinChallenge!.attemptsRemaining, 0);
    final calls = pins.unlocks;
    expect(await session.submitPin('0427'), isFalse);
    expect(pins.unlocks, calls);
    final previous = session;
    session = SessionController(auth, vault, pinGateway: pins);
    previous.dispose();
    await session.initialize();
    expect(session.pinChallenge!.recoveryRequired, isTrue);
  });

  test('forgot PIN requires identity verification then create and confirm a replacement', () async {
    await setup();
    session.lockApp();
    await Future<void>.delayed(Duration.zero);
    await session.forgotPin();
    expect(session.phase, SessionPhase.signedOut);
    expect(vault.refreshToken, isNull);
    await email();
    expect(session.pinStage, PinStage.create);
    expect(session.pinResetting, isTrue);
    await session.submitPin('8195');
    await session.submitPin('8195');
    session.lockApp();
    await Future<void>.delayed(Duration.zero);
    expect(await session.submitPin('0427'), isFalse);
    expect(await session.submitPin('8195'), isTrue);
  });

  test(
    'recovery for one customer cannot silently reset another customer PIN',
    () async {
      await setup();
      session.lockApp();
      await Future<void>.delayed(Duration.zero);
      await session.forgotPin();
      await email('other@example.test');
      await session.completeInformation('Other', 'Customer');
      expect(session.pinStage, PinStage.create);
      expect(session.pinResetting, isFalse);
    },
  );

  test(
    'backgrounding during an unlock cannot publish its late banking tokens',
    () async {
      await setup();
      session.lockApp();
      await Future<void>.delayed(Duration.zero);
      pins.unlockGate = Completer<void>();
      final unlocking = session.submitPin('0427');
      await Future<void>.delayed(Duration.zero);
      session.lockApp();
      pins.unlockGate!.complete();
      expect(await unlocking, isFalse);
      expect(session.phase, SessionPhase.pinLocked);
      expect(vault.refreshToken, startsWith('kesor-pin-v1:'));
    },
  );

  test(
    'photo-picker handoff expires and cannot keep the app unlocked',
    () async {
      var now = DateTime(2026, 10, 30);
      session.dispose();
      session = SessionController(
        auth,
        vault,
        pinGateway: pins,
        clock: () => now,
      );
      await session.initialize();
      await setup();
      session.beginPhotoSelection();
      session.coverPrivateContent();
      expect(session.privacyCovered, isTrue);
      expect(session.trustedPhotoSelection, isTrue);
      now = now.add(const Duration(seconds: 61));
      expect(session.trustedPhotoSelection, isFalse);
      session.endPhotoSelection();
      await Future<void>.delayed(Duration.zero);
      expect(session.phase, SessionPhase.pinLocked);
    },
  );

  testWidgets(
    'keypad starts empty, preserves leading zero and supports clear and delete',
    (tester) async {
      await tester.runAsync(onboard);
      await tester.pumpWidget(
        BankingApp(
          session: session,
          config: AppConfig(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            environment: 'dev',
            mode: 'demo',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('pin-input'));
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      Future<void> tap(String key) async {
        final target = find.byKey(ValueKey(key));
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      await tap('pin-digit-0');
      await tap('pin-digit-4');
      expect(tester.widget<TextField>(field).controller!.text, '04');
      await tap('pin-delete');
      expect(tester.widget<TextField>(field).controller!.text, '0');
      await tap('pin-clear');
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      for (final digit in [0, 4, 2, 7]) {
        await tap('pin-digit-$digit');
      }
      expect(find.text('Confirm PIN'), findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      await tester.enterText(field, '0427');
      // The vault serialization future was created by setUp outside FakeAsync.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(session.phase, SessionPhase.signedIn);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'inactive conceals private UI; only 3 minutes away or idle requires the PIN',
    (tester) async {
      // User decision (31 Oct 2026): one PIN per use; re-ask after 3 minutes.
      var now = DateTime.utc(2026, 10, 31, 9);
      session.dispose();
      session = SessionController(
        auth,
        vault,
        pinGateway: pins,
        clock: () => now,
      );
      await tester.runAsync(session.initialize);
      void background() {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      }

      void resume() {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }

      await tester.runAsync(setup);
      await tester.pumpWidget(
        BankingApp(
          session: session,
          config: AppConfig(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            environment: 'dev',
            mode: 'demo',
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(session.privacyCovered, isTrue);
      // A short trip away keeps the session.
      background();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      now = now.add(const Duration(minutes: 2));
      resume();
      await tester.pumpAndSettle();
      expect(session.phase, SessionPhase.signedIn);
      expect(session.privacyCovered, isFalse);
      // Idle for 3 minutes locks.
      now = now.add(SessionController.idleLimit);
      session.checkIdle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(session.phase, SessionPhase.pinLocked);
      // The lock starts on the masked Home; a feature tap shows the PIN pad.
      expect(find.byKey(const ValueKey('locked-home')), findsOneWidget);
      expect(find.text('Enter PIN'), findsNothing);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Enter PIN'), findsOneWidget);
      final field = find.byKey(const ValueKey('pin-input'));
      await tester.enterText(field, '04');
      background();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      resume();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
