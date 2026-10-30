import 'dart:convert';
import 'dart:typed_data';

import '../../../core/network/api_client.dart';
import 'profile_photo.dart';

class SessionIdentity {
  const SessionIdentity({
    required this.userId,
    required this.username,
    required this.email,
    required this.roles,
    required this.sessionId,
    this.profileComplete = true,
    this.firstName,
    this.lastName,
    this.telegramLinked = false,
  });
  factory SessionIdentity.fromJson(Map<String, dynamic> data) {
    if (data['userId'] is! int ||
        data['username'] is! String ||
        (data['email'] != null && data['email'] is! String) ||
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
      email: data['email'] as String?,
      roles: List<String>.from(data['roles'] as List),
      sessionId: data['sessionId'] as String,
      profileComplete: data['profileComplete'] as bool? ?? true,
      firstName: data['firstName'] as String?,
      lastName: data['lastName'] as String?,
      telegramLinked: data['telegramLinked'] as bool? ?? false,
    );
  }
  final int userId;
  final String username;
  final String? email;
  final List<String> roles;
  final String sessionId;
  final bool profileComplete, telegramLinked;
  final String? firstName, lastName;
  String get displayName => [
    firstName,
    lastName,
  ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
}

abstract interface class ContinuationGateway {
  Future<OtpReceipt> requestContinueOtp(String email, {String? linkToken});
  Future<TokenPair> verifyEmail(
    Map<String, dynamic> payload, {
    String? linkToken,
  });
  Future<SessionIdentity> completeProfile(
    String access,
    String firstName,
    String lastName,
  );
  Future<Map<String, dynamic>> startTelegram(
    Map<String, dynamic> device, {
    String? linkToken,
  });
  Future<Map<String, dynamic>> exchangeTelegram(
    String flowId,
    String exchangeSecret, {
    String? approvalReceipt,
  });
}

abstract interface class NativeTelegramGateway {
  Future<Map<String, dynamic>> startNativeTelegram(
    Map<String, dynamic> device, {
    String? linkToken,
  });
  Future<TokenPair> exchangeNativeTelegram(
    String flowId,
    String exchangeSecret,
    String code,
  );
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

class HttpAuthGateway
    implements AuthGateway, ContinuationGateway, NativeTelegramGateway {
  HttpAuthGateway(this.client);
  final ApiClient client;
  @override
  Future<Map<String, dynamic>> startNativeTelegram(
    Map<String, dynamic> device, {
    String? linkToken,
  }) async => _data(
    await client.request(
      'POST',
      linkToken == null
          ? '/auth/telegram/native/start'
          : '/auth/telegram/native/link/start',
      accessToken: linkToken,
      body: device,
    ),
  );
  @override
  Future<TokenPair> exchangeNativeTelegram(
    String flowId,
    String exchangeSecret,
    String code,
  ) async => TokenPair.fromJson(
    _data(
      await client.request(
        'POST',
        '/auth/telegram/native/exchange',
        body: {
          'flowId': flowId,
          'exchangeSecret': exchangeSecret,
          'code': code,
        },
      ),
    ),
  );
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
  Future<OtpReceipt> requestContinueOtp(
    String email, {
    String? linkToken,
  }) async => OtpReceipt.fromJson(
    _data(
      await client.request(
        'POST',
        linkToken == null ? '/auth/email/request' : '/auth/email/link/request',
        accessToken: linkToken,
        body: {'email': email},
      ),
    ),
  );
  @override
  Future<TokenPair> verifyEmail(
    Map<String, dynamic> payload, {
    String? linkToken,
  }) async => TokenPair.fromJson(
    _data(
      await client.request(
        'POST',
        linkToken == null ? '/auth/email/verify' : '/auth/email/link/verify',
        accessToken: linkToken,
        body: payload,
      ),
    ),
  );
  @override
  Future<SessionIdentity> completeProfile(
    String access,
    String firstName,
    String lastName,
  ) async => SessionIdentity.fromJson(
    _data(
      await client.request(
        'PATCH',
        '/auth/profile',
        accessToken: access,
        body: {'firstName': firstName, 'lastName': lastName},
      ),
    ),
  );
  @override
  Future<Map<String, dynamic>> startTelegram(
    Map<String, dynamic> device, {
    String? linkToken,
  }) async => _data(
    await client.request(
      'POST',
      linkToken == null ? '/auth/telegram/start' : '/auth/telegram/link/start',
      accessToken: linkToken,
      body: device,
    ),
  );
  @override
  Future<Map<String, dynamic>> exchangeTelegram(
    String flowId,
    String exchangeSecret, {
    String? approvalReceipt,
  }) async => _data(
    await client.request(
      'POST',
      '/auth/telegram/exchange',
      body: {
        'flowId': flowId,
        'exchangeSecret': exchangeSecret,
        'approvalReceipt': approvalReceipt,
      },
    ),
  );

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
class DemoAuthGateway
    implements AuthGateway, ContinuationGateway, ProfilePhotoGateway {
  final Map<int, ProfilePhoto> _photos = {};
  @override
  Future<ProfilePhoto?> readPhoto(String access) async =>
      _photos[(await me(access)).userId];
  @override
  Future<ProfilePhoto> savePhoto(String access, Uint8List bytes) async {
    final photo = ProfilePhoto(
      bytes,
      bytes.length > 2 && bytes[0] == 0x89 ? 'image/png' : 'image/jpeg',
    );
    _photos[(await me(access)).userId] = photo;
    return photo;
  }

  final Map<String, SessionIdentity> _access = {};
  final Map<String, SessionIdentity> _profiles = {};
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
          'profileComplete': identity.profileComplete,
          'firstName': identity.firstName,
          'lastName': identity.lastName,
          'telegramLinked': identity.telegramLinked,
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
      final previous = SessionIdentity.fromJson(
        jsonDecode(utf8.decode(base64Url.decode(refreshToken.substring(10))))
            as Map<String, dynamic>,
      );
      return _issue(_profiles[previous.email] ?? previous);
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

  @override
  Future<OtpReceipt> requestContinueOtp(
    String email, {
    String? linkToken,
  }) async => const OtpReceipt(resendAfterSeconds: 5);
  @override
  Future<TokenPair> verifyEmail(
    Map<String, dynamic> payload, {
    String? linkToken,
  }) async {
    if (payload['otpCode'] != '123456') {
      throw ApiFailure(
        'OTP_INVALID',
        ApiFailure.messageFor('OTP_INVALID'),
        status: 401,
      );
    }
    final email = payload['email'] as String;
    final identity = _profiles.putIfAbsent(
      email,
      () => SessionIdentity(
        userId: _profiles.length + 1,
        username: 'demo.customer',
        email: email,
        roles: const ['ROLE_CUSTOMER'],
        sessionId: 'demo-session',
        profileComplete: false,
      ),
    );
    return _issue(identity);
  }

  @override
  Future<SessionIdentity> completeProfile(
    String access,
    String firstName,
    String lastName,
  ) async {
    final previous = await me(access);
    final identity = SessionIdentity(
      userId: previous.userId,
      username: previous.username,
      email: previous.email,
      roles: previous.roles,
      sessionId: previous.sessionId,
      firstName: firstName,
      lastName: lastName,
      telegramLinked: previous.telegramLinked,
    );
    _access[access] = identity;
    if (identity.email != null) _profiles[identity.email!] = identity;
    return identity;
  }

  @override
  Future<Map<String, dynamic>> startTelegram(
    Map<String, dynamic> device, {
    String? linkToken,
  }) async => throw const ApiFailure(
    'TELEGRAM_UNAVAILABLE',
    'Telegram requires live API mode. Use email to explore this demo.',
  );
  @override
  Future<Map<String, dynamic>> exchangeTelegram(
    String flowId,
    String exchangeSecret, {
    String? approvalReceipt,
  }) async => throw const ApiFailure(
    'TELEGRAM_UNAVAILABLE',
    'Telegram requires live API mode.',
  );
}
