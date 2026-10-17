import 'dart:async';

import 'package:customer_app/core/network/api_client.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/auth/data/auth_gateway.dart';

class FakeGateway implements AuthGateway {
  int otpCalls = 0, refreshCalls = 0, authCalls = 0, logoutCalls = 0;
  int expiresInMs = 1000;
  Map<String, dynamic>? lastPayload;
  String? purpose;
  ApiFailure? otpFailure, authFailure, refreshFailure, meFailure, logoutFailure;
  Completer<void>? refreshGate, logoutGate;
  final List<String> loggedOut = [];
  Future<SessionIdentity> Function(String)? onMe;
  SessionIdentity profile = const SessionIdentity(
    userId: 1,
    username: 'customer',
    email: 'customer@example.test',
    roles: ['ROLE_CUSTOMER'],
    sessionId: 'session',
  );
  @override
  Future<OtpReceipt> requestOtp(String email, String purpose) async {
    otpCalls++;
    this.purpose = purpose;
    if (otpFailure != null) throw otpFailure!;
    return const OtpReceipt();
  }

  TokenPair pair(String suffix) => TokenPair(
    accessToken: 'access-$suffix',
    refreshToken: 'refresh-$suffix',
    expiresInMs: expiresInMs,
  );
  @override
  Future<TokenPair> authenticate(
    Map<String, dynamic> payload, {
    required bool register,
  }) async {
    authCalls++;
    lastPayload = payload;
    if (authFailure != null) throw authFailure!;
    return pair('login');
  }

  @override
  Future<TokenPair> refresh(String refreshToken) async {
    refreshCalls++;
    await refreshGate?.future;
    if (refreshFailure != null) throw refreshFailure!;
    return pair('rotated-$refreshCalls');
  }

  @override
  Future<SessionIdentity> me(String accessToken) async {
    if (onMe != null) return onMe!(accessToken);
    if (meFailure != null) throw meFailure!;
    return profile;
  }

  @override
  Future<void> logout(String accessToken) async {
    logoutCalls++;
    loggedOut.add(accessToken);
    await logoutGate?.future;
    if (logoutFailure != null) throw logoutFailure!;
  }
}

class FailingVault extends MemorySessionVault {
  bool failRead = false, failWrite = false, failId = false;
  @override
  Future<String?> readRefreshToken() async {
    if (failRead) throw StateError('Storage unavailable');
    return super.readRefreshToken();
  }

  @override
  Future<void> writeRefreshToken(String? token) async {
    if (failWrite) throw StateError('Storage unavailable');
    await super.writeRefreshToken(token);
  }

  @override
  Future<String> installationId() async {
    if (failId) throw StateError('Storage unavailable');
    return super.installationId();
  }
}
