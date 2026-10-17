import 'dart:async';

import 'package:customer_app/core/network/api_client.dart';
import 'package:customer_app/features/auth/data/auth_gateway.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  late FakeGateway gateway;
  late FailingVault vault;
  late SessionController session;
  late DateTime now;
  setUp(() async {
    gateway = FakeGateway();
    vault = FailingVault();
    now = DateTime(2026);
    session = SessionController(gateway, vault, clock: () => now);
    await session.initialize();
  });
  tearDown(() => session.dispose());
  Future<void> start({bool register = false}) async {
    session.openForm(register: register);
    expect(
      await session.begin(
        email: ' Customer@Example.Test ',
        password: 'Secret123!',
        username: 'customer',
        register: register,
      ),
      true,
    );
  }

  Future<void> login() async {
    await start();
    expect(await session.verifyCode('123456'), true);
  }

  test(
    'signup sends normalized email, device ID and code only to final endpoint',
    () async {
      await start(register: true);
      expect(gateway.authCalls, 0);
      expect(gateway.purpose, 'SIGNUP');
      expect(session.otpEmail, 'customer@example.test');
      expect(await session.verifyCode('123456'), true);
      expect(gateway.lastPayload!['email'], 'customer@example.test');
      expect(gateway.lastPayload!['otpCode'], '123456');
      expect(
        gateway.lastPayload!['deviceFingerprint'],
        await vault.installationId(),
      );
      expect(session.phase, SessionPhase.signedIn);
      expect(session.otpEmail, '');
      expect(await vault.readRefreshToken(), 'refresh-login');
    },
  );
  test('login uses email identifier and LOGIN purpose', () async {
    await login();
    expect(gateway.purpose, 'LOGIN');
    expect(gateway.lastPayload!['usernameOrEmail'], 'customer@example.test');
    expect(gateway.lastPayload!.containsKey('email'), false);
  });
  test('wrong OTP keeps draft for retry without saving session', () async {
    await start();
    gateway.authFailure = const ApiFailure(
      'OTP_INVALID',
      'Wrong code',
      status: 401,
    );
    expect(await session.verifyCode('000000'), false);
    expect(session.screen, AuthScreen.otp);
    expect(session.phase, SessionPhase.signedOut);
    expect(await vault.readRefreshToken(), null);
    gateway.authFailure = null;
    expect(await session.verifyCode('123456'), true);
  });
  test('resend respects server cooldown and rate-limit retry', () async {
    await start();
    await session.resend();
    expect(gateway.otpCalls, 1);
    now = now.add(const Duration(seconds: 60));
    gateway.otpFailure = const ApiFailure(
      'OTP_RATE_LIMITED',
      'Wait',
      retryAfterSeconds: 90,
    );
    await session.resend();
    expect(session.resendSeconds, 90);
    now = now.add(const Duration(seconds: 90));
    gateway.otpFailure = null;
    await session.resend();
    expect(session.expirySeconds, 300);
    expect(gateway.otpCalls, 3);
  });
  test('pending password is discarded on back and after ten minutes', () async {
    await start();
    session.back();
    expect(await session.verifyCode('123456'), false);
    await start();
    now = now.add(const Duration(minutes: 10));
    session.expirePendingIfNeeded();
    expect(session.screen, AuthScreen.login);
    expect(session.otpEmail, '');
    expect(await session.verifyCode('123456'), false);
  });
  test(
    'stored session restores by rotating and persisting replacement',
    () async {
      vault.refreshToken = 'previous';
      await session.initialize();
      expect(gateway.refreshCalls, 1);
      expect(session.phase, SessionPhase.signedIn);
      expect(await vault.readRefreshToken(), 'refresh-rotated-1');
    },
  );
  test(
    'expired access coordinates concurrent reads into one refresh',
    () async {
      await login();
      now = now.add(const Duration(seconds: 2));
      gateway.refreshGate = Completer<void>();
      final reads = [
        session.checkIdentity(),
        session.checkIdentity(),
        session.checkIdentity(),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(gateway.refreshCalls, 1);
      expect(await vault.readRefreshToken(), null);
      gateway.refreshGate!.complete();
      await Future.wait(reads);
      expect(gateway.refreshCalls, 1);
      expect(session.phase, SessionPhase.signedIn);
    },
  );
  test('uncertain refresh is consumed, cleared and never retried', () async {
    await login();
    now = now.add(const Duration(seconds: 2));
    gateway.refreshFailure = const ApiFailure('TIMEOUT', 'Timed out');
    await expectLater(session.checkIdentity(), throwsA(isA<ApiFailure>()));
    expect(session.phase, SessionPhase.signedOut);
    expect(session.identity, null);
    expect(await vault.readRefreshToken(), null);
    await session.initialize();
    expect(gateway.refreshCalls, 1);
  });
  test(
    'server session revocation clears private state and persisted token',
    () async {
      await login();
      gateway.meFailure = const ApiFailure(
        'SESSION_INVALID',
        'Revoked',
        status: 401,
      );
      await expectLater(session.checkIdentity(), throwsA(isA<ApiFailure>()));
      expect(session.phase, SessionPhase.signedOut);
      expect(session.identity, null);
      expect(await vault.readRefreshToken(), null);
      expect(gateway.refreshCalls, 0);
    },
  );
  test('non-customer session is revoked before persistence', () async {
    await start();
    gateway.profile = const SessionIdentity(
      userId: 2,
      username: 'staff',
      email: 'staff@example.test',
      roles: ['ROLE_EMPLOYEE'],
      sessionId: 'staff-session',
    );
    expect(await session.verifyCode('123456'), false);
    expect(session.failure!.code, 'CUSTOMER_REQUIRED');
    expect(gateway.logoutCalls, 1);
    expect(await vault.readRefreshToken(), null);
  });
  test(
    'secure storage failure blocks authentication without memory fallback',
    () async {
      vault.failId = true;
      await session.begin(
        email: 'x@example.test',
        password: 'Password1!',
        register: false,
      );
      expect(session.phase, SessionPhase.storageError);
      expect(gateway.otpCalls, 0);
      vault.failId = false;
      await session.initialize();
      expect(session.phase, SessionPhase.signedOut);
    },
  );
  test('failed secure write revokes newly issued server session', () async {
    await start();
    vault.failWrite = true;
    expect(await session.verifyCode('123456'), false);
    expect(session.phase, SessionPhase.storageError);
    expect(session.identity, null);
    expect(gateway.logoutCalls, 1);
    vault.failWrite = false;
    await session.initialize();
    expect(session.phase, SessionPhase.signedOut);
    expect(session.screen, AuthScreen.welcome);
    expect(session.busy, false);
  });
  test(
    'logout hides private state immediately and preserves installation ID',
    () async {
      await login();
      final id = await vault.installationId();
      gateway.logoutGate = Completer<void>();
      final logout = session.signOut();
      expect(session.phase, SessionPhase.signedOut);
      expect(session.identity, null);
      await Future<void>.delayed(Duration.zero);
      expect(await vault.readRefreshToken(), null);
      gateway.logoutGate!.complete();
      await logout;
      expect(await vault.installationId(), id);
      expect(session.notice, 'You have signed out.');
    },
  );
  test(
    'offline logout clears local state and reports unconfirmed revocation',
    () async {
      await login();
      gateway.logoutFailure = gateway.refreshFailure = const ApiFailure(
        'OFFLINE',
        'Offline',
      );
      await session.signOut();
      expect(session.phase, SessionPhase.signedOut);
      expect(await vault.readRefreshToken(), null);
      expect(session.notice, contains('could not be confirmed'));
    },
  );
  test(
    'logout during refresh cannot restore private content or replay old token',
    () async {
      await login();
      now = now.add(const Duration(seconds: 2));
      gateway.refreshGate = Completer<void>();
      final read = session.checkIdentity();
      final readSettled = read.then((_) {}, onError: (Object e) {});
      await Future<void>.delayed(Duration.zero);
      final logout = session.signOut();
      gateway.refreshGate!.complete();
      await Future.wait([logout, readSettled]);
      expect(session.phase, SessionPhase.signedOut);
      expect(session.identity, null);
      expect(await vault.readRefreshToken(), null);
      expect(gateway.refreshCalls, 1);
      expect(gateway.loggedOut, contains('access-rotated-1'));
    },
  );
  test('network profile failure keeps established session for retry', () async {
    await login();
    gateway.meFailure = const ApiFailure('OFFLINE', 'Offline');
    await session.refreshProfile();
    expect(session.phase, SessionPhase.signedIn);
    expect(session.failure!.code, 'OFFLINE');
  });
  test('late concurrent TOKEN_INVALID responses reuse the already rotated access token', () async {
    await login();
    final failures = [
      Completer<SessionIdentity>(),
      Completer<SessionIdentity>(),
    ];
    var oldRequests = 0;
    gateway.onMe = (access) async => access == 'access-login'
        ? failures[oldRequests++].future
        : gateway.profile;
    final first = session.checkIdentity();
    final second = session.checkIdentity();
    failures[0].completeError(
      const ApiFailure('TOKEN_INVALID', 'Expired', status: 401),
    );
    await first;
    expect(gateway.refreshCalls, 1);
    failures[1].completeError(
      const ApiFailure('TOKEN_INVALID', 'Expired', status: 401),
    );
    await second;
    expect(gateway.refreshCalls, 1);
  });
  test('a late successful read cannot repopulate private identity after invalidation', () async {
    await login();
    final late = Completer<SessionIdentity>();
    var calls = 0;
    gateway.onMe = (_) async {
      if (calls++ == 0) return late.future;
      throw const ApiFailure('SESSION_INVALID', 'Revoked', status: 401);
    };
    final pending = session.checkIdentity();
    final settled = expectLater(pending, throwsA(isA<Exception>()));
    await expectLater(session.checkIdentity(), throwsA(isA<ApiFailure>()));
    late.complete(gateway.profile);
    await settled;
    expect(session.phase, SessionPhase.signedOut);
    expect(session.identity, null);
    expect(session.busy, false);
    expect(await vault.readRefreshToken(), null);
  });
  for (final code in ['USER_DISABLED', 'DEVICE_REVOKED']) {
    test(
      '$code clears saved and private session without a renewal loop',
      () async {
        await login();
        gateway.meFailure = ApiFailure(code, 'Access ended', status: 401);
        await session.refreshProfile();
        expect(session.phase, SessionPhase.signedOut);
        expect(session.identity, null);
        expect(await vault.readRefreshToken(), null);
        expect(gateway.refreshCalls, 0);
      },
    );
  }
}
