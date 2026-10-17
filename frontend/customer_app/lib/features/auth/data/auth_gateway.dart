import 'dart:convert';

import '../../../core/network/api_client.dart';

class SessionIdentity {
  const SessionIdentity({
    required this.userId,
    required this.username,
    required this.email,
    required this.roles,
    required this.sessionId,
  });
  factory SessionIdentity.fromJson(Map<String, dynamic> data) {
    if (data['userId'] is! int ||
        data['username'] is! String ||
        data['email'] is! String ||
        data['sessionId'] is! String ||
        data['roles'] is! List ||
        (data['roles'] as List).any((r) => r is! String)) {
      throw const ApiFailure(
        'INVALID_RESPONSE',
        'Your profile could not be verified. Please sign in again.',
      );
    }
    return SessionIdentity(
      userId: data['userId'] as int,
      username: data['username'] as String,
      email: data['email'] as String,
      roles: List<String>.from(data['roles'] as List),
      sessionId: data['sessionId'] as String,
    );
  }
  final int userId;
  final String username;
  final String email;
  final List<String> roles;
  final String sessionId;
}

class TokenPair {
  TokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresInMs,
  });
  factory TokenPair.fromJson(Map<String, dynamic> data) {
    if (data['accessToken'] is! String ||
        (data['accessToken'] as String).isEmpty ||
        data['refreshToken'] is! String ||
        (data['refreshToken'] as String).isEmpty ||
        data['expiresInMs'] is! int ||
        (data['expiresInMs'] as int) <= 0) {
      throw const ApiFailure(
        'INVALID_RESPONSE',
        'Your session could not be confirmed. Please sign in again.',
      );
    }
    return TokenPair(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
      expiresInMs: data['expiresInMs'] as int,
    );
  }
  final String accessToken;
  final String refreshToken;
  final int expiresInMs;
}

class OtpReceipt {
  const OtpReceipt({this.expiresInSeconds = 300, this.resendAfterSeconds = 60});
  factory OtpReceipt.fromJson(Map<String, dynamic> data) {
    if (data['expiresInSeconds'] is! int ||
        data['resendAfterSeconds'] is! int ||
        (data['expiresInSeconds'] as int) <= 0 ||
        (data['resendAfterSeconds'] as int) < 0) {
      throw const ApiFailure(
        'INVALID_RESPONSE',
        'Your code request could not be confirmed. Please try again.',
      );
    }
    return OtpReceipt(
      expiresInSeconds: data['expiresInSeconds'] as int,
      resendAfterSeconds: data['resendAfterSeconds'] as int,
    );
  }
  final int expiresInSeconds;
  final int resendAfterSeconds;
}

abstract interface class AuthGateway {
  Future<OtpReceipt> requestOtp(String email, String purpose);
  Future<TokenPair> authenticate(
    Map<String, dynamic> payload, {
    required bool register,
  });
  Future<TokenPair> refresh(String refreshToken);
  Future<SessionIdentity> me(String accessToken);
  Future<void> logout(String accessToken);
}

class HttpAuthGateway implements AuthGateway {
  HttpAuthGateway(this.client);
  final ApiClient client;
  Map<String, dynamic> _data(Map<String, dynamic> response) {
    if (response['data'] is! Map<String, dynamic>) {
      throw const ApiFailure(
        'INVALID_RESPONSE',
        'The service returned incomplete information.',
      );
    }
    return response['data'] as Map<String, dynamic>;
  }

  @override
  Future<OtpReceipt> requestOtp(String email, String purpose) async =>
      OtpReceipt.fromJson(
        _data(
          await client.request(
            'POST',
            '/auth/request-otp',
            body: {'email': email, 'purpose': purpose},
          ),
        ),
      );
  @override
  Future<TokenPair> authenticate(
    Map<String, dynamic> payload, {
    required bool register,
  }) async => TokenPair.fromJson(
    _data(
      await client.request(
        'POST',
        register ? '/auth/register' : '/auth/login',
        body: payload,
      ),
    ),
  );
  @override
  Future<TokenPair> refresh(String refreshToken) async => TokenPair.fromJson(
    _data(
      await client.request(
        'POST',
        '/auth/refresh',
        body: {'refreshToken': refreshToken},
      ),
    ),
  );
  @override
  Future<SessionIdentity> me(String accessToken) async =>
      SessionIdentity.fromJson(
        _data(
          await client.request('GET', '/auth/me', accessToken: accessToken),
        ),
      );
  @override
  Future<void> logout(String accessToken) async {
    await client.request('POST', '/auth/logout', accessToken: accessToken);
  }
}

/// Explicit development-only UI simulation. Never selected following an API error.
class DemoAuthGateway implements AuthGateway {
  final Map<String, SessionIdentity> _access = {};
  int _sequence = 0;
  @override
  Future<OtpReceipt> requestOtp(String email, String purpose) async =>
      const OtpReceipt(resendAfterSeconds: 5);
  TokenPair _issue(SessionIdentity identity) {
    final access = 'demo-access-${++_sequence}';
    _access[access] = identity;
    final refresh = base64Url.encode(
      utf8.encode(
        jsonEncode({
          'userId': identity.userId,
          'username': identity.username,
          'email': identity.email,
          'roles': identity.roles,
          'sessionId': identity.sessionId,
        }),
      ),
    );
    return TokenPair(
      accessToken: access,
      refreshToken: 'demo-only:$refresh',
      expiresInMs: 900000,
    );
  }

  @override
  Future<TokenPair> authenticate(
    Map<String, dynamic> payload, {
    required bool register,
  }) async {
    if (payload['otpCode'] != '123456') {
      throw ApiFailure(
        'OTP_INVALID',
        ApiFailure.messageFor('OTP_INVALID'),
        status: 401,
      );
    }
    final email = (payload[register ? 'email' : 'usernameOrEmail'] as String);
    return _issue(
      SessionIdentity(
        userId: 1,
        username: payload['username'] as String? ?? 'demo.customer',
        email: email,
        roles: const ['ROLE_CUSTOMER'],
        sessionId: 'demo-session',
      ),
    );
  }

  @override
  Future<TokenPair> refresh(String refreshToken) async {
    try {
      if (!refreshToken.startsWith('demo-only:')) throw const FormatException();
      return _issue(
        SessionIdentity.fromJson(
          jsonDecode(utf8.decode(base64Url.decode(refreshToken.substring(10))))
              as Map<String, dynamic>,
        ),
      );
    } catch (_) {
      throw const ApiFailure(
        'SESSION_INVALID',
        'This demo session ended. Sign in again.',
        status: 401,
      );
    }
  }

  @override
  Future<SessionIdentity> me(String accessToken) async {
    final identity = _access[accessToken];
    if (identity == null) {
      throw const ApiFailure('SESSION_INVALID', 'Sign in again.', status: 401);
    }
    return identity;
  }

  @override
  Future<void> logout(String accessToken) async {
    _access.remove(accessToken);
  }
}
