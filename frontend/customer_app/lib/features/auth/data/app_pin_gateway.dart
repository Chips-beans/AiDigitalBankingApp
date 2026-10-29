import 'dart:convert';
import 'dart:math';

import '../../../core/network/api_client.dart';
import 'auth_gateway.dart';

class PinChallenge {
  const PinChallenge({
    required this.ticket,
    required this.userId,
    required this.configured,
    required this.attemptsRemaining,
    required this.recoveryRequired,
    required this.canRecover,
    required this.displayName,
  });
  final String ticket, displayName;
  final bool configured, recoveryRequired, canRecover;
  final int attemptsRemaining, userId;
  factory PinChallenge.fromJson(Map<String, dynamic> json) {
    if (json['userId'] is! int ||
        (json['userId'] as int) <= 0 ||
        json['ticket'] is! String ||
        (json['ticket'] as String).isEmpty ||
        json['displayName'] is! String ||
        json['configured'] is! bool ||
        json['recoveryRequired'] is! bool ||
        json['canRecover'] is! bool ||
        json['attemptsRemaining'] is! int ||
        (json['attemptsRemaining'] as int) < 0 ||
        (json['attemptsRemaining'] as int) > 5) {
      throw const ApiFailure(
        'INVALID_RESPONSE',
        'The app lock could not be confirmed.',
      );
    }
    return PinChallenge(
      ticket: json['ticket'] as String,
      userId: json['userId'] as int,
      configured: json['configured'] as bool,
      attemptsRemaining: json['attemptsRemaining'] as int,
      recoveryRequired: json['recoveryRequired'] as bool,
      canRecover: json['canRecover'] as bool,
      displayName: json['displayName'] as String,
    );
  }
  Map<String, dynamic> toJson() => {
    'ticket': ticket,
    'userId': userId,
    'configured': configured,
    'attemptsRemaining': attemptsRemaining,
    'recoveryRequired': recoveryRequired,
    'canRecover': canRecover,
    'displayName': displayName,
  };
  String encode() => 'kesor-pin-v1:${jsonEncode(toJson())}';
  static PinChallenge decode(String value) => PinChallenge.fromJson(
    jsonDecode(value.substring('kesor-pin-v1:'.length)) as Map<String, dynamic>,
  );
}

abstract interface class AppPinGateway {
  Future<PinChallenge> prepare(String access);
  Future<PinChallenge> status(String ticket);
  Future<TokenPair> setup(
    String ticket,
    String pin,
    String confirmPin, {
    required bool reset,
  });
  Future<TokenPair> unlock(String ticket, String pin);
  Future<void> discard(String ticket);
}

class HttpAppPinGateway implements AppPinGateway {
  HttpAppPinGateway(this.client);
  final ApiClient client;
  Map<String, dynamic> data(Map<String, dynamic> response) {
    if (response['data'] is! Map<String, dynamic>) {
      throw const ApiFailure(
        'INVALID_RESPONSE',
        'The app lock could not be confirmed.',
      );
    }
    return response['data'] as Map<String, dynamic>;
  }

  @override
  Future<PinChallenge> prepare(String access) async => PinChallenge.fromJson(
    data(
      await client.request('POST', '/auth/pin/prepare', accessToken: access),
    ),
  );
  @override
  Future<PinChallenge> status(String ticket) async => PinChallenge.fromJson(
    data(
      await client.request(
        'POST',
        '/auth/pin/status',
        body: {'ticket': ticket},
      ),
    ),
  );
  @override
  Future<TokenPair> setup(
    String ticket,
    String pin,
    String confirmPin, {
    required bool reset,
  }) async => TokenPair.fromJson(
    data(
      await client.request(
        'POST',
        '/auth/pin/setup',
        body: {
          'ticket': ticket,
          'pin': pin,
          'confirmPin': confirmPin,
          'reset': reset,
        },
      ),
    ),
  );
  @override
  Future<TokenPair> unlock(String ticket, String pin) async =>
      TokenPair.fromJson(
        data(
          await client.request(
            'POST',
            '/auth/pin/unlock',
            body: {'ticket': ticket, 'pin': pin},
          ),
        ),
      );
  @override
  Future<void> discard(String ticket) async {
    await client.request('POST', '/auth/pin/discard', body: {'ticket': ticket});
  }
}

/// Explicit demo only. Real deployments always use the server-enforced gateway.
class DemoAppPinGateway implements AppPinGateway {
  DemoAppPinGateway(this.auth);
  final AuthGateway auth;
  final Map<String, (SessionIdentity, TokenPair?)> tickets = {};
  final Map<int, String> _pins = {};
  final Map<int, int> _attempts = {};
  final Set<String> _fresh = {};
  PinChallenge challenge(String ticket) {
    final user = tickets[ticket]?.$1;
    if (user == null) {
      throw const ApiFailure(
        'PIN_TICKET_INVALID',
        'Sign in again.',
        status: 401,
      );
    }
    return PinChallenge(
      ticket: ticket,
      userId: user.userId,
      configured: _pins.containsKey(user.userId),
      attemptsRemaining: 5 - (_attempts[user.userId] ?? 0),
      recoveryRequired: (_attempts[user.userId] ?? 0) >= 5,
      canRecover: _fresh.contains(ticket),
      displayName: user.displayName.isEmpty ? user.username : user.displayName,
    );
  }

  @override
  Future<PinChallenge> prepare(String access) async {
    final user = await auth.me(access);
    final random = Random.secure();
    final ticket =
        'demo-pin-${List.generate(24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    tickets[ticket] = (user, null);
    _fresh.add(ticket);
    return challenge(ticket);
  }

  @override
  Future<PinChallenge> status(String ticket) async => challenge(ticket);
  Future<TokenPair> issue(String ticket) async {
    final user = tickets[ticket]!.$1;
    // DemoAuthGateway.refresh consumes its explicit demo-only serialized identity.
    final refresh =
        'demo-only:${base64Url.encode(utf8.encode(jsonEncode({'userId': user.userId, 'username': user.username, 'email': user.email, 'roles': user.roles, 'sessionId': user.sessionId, 'profileComplete': user.profileComplete, 'firstName': user.firstName, 'lastName': user.lastName, 'telegramLinked': user.telegramLinked})))}';
    _fresh.remove(ticket);
    return auth.refresh(refresh);
  }

  @override
  Future<TokenPair> setup(
    String ticket,
    String pin,
    String confirmPin, {
    required bool reset,
  }) async {
    final state = challenge(ticket);
    if (pin != confirmPin || !RegExp(r'^[0-9]{4}$').hasMatch(pin)) {
      throw const ApiFailure('PIN_CONFIRMATION_MISMATCH', 'PINs do not match.');
    }
    if (state.configured && (!reset || !state.canRecover)) {
      throw const ApiFailure(
        'PIN_RECOVERY_AUTH_REQUIRED',
        'Verify your identity again.',
      );
    }
    _pins[tickets[ticket]!.$1.userId] = pin;
    _attempts[tickets[ticket]!.$1.userId] = 0;
    return issue(ticket);
  }

  @override
  Future<TokenPair> unlock(String ticket, String pin) async {
    final state = challenge(ticket);
    final id = tickets[ticket]!.$1.userId;
    if (state.recoveryRequired) {
      throw const ApiFailure(
        'PIN_RECOVERY_REQUIRED',
        'Verify your identity to reset your PIN.',
      );
    }
    if (_pins[id] != pin) {
      _attempts[id] = (_attempts[id] ?? 0) + 1;
      throw ApiFailure(
        _attempts[id] == 5 ? 'PIN_RECOVERY_REQUIRED' : 'PIN_INVALID',
        'Incorrect PIN.',
      );
    }
    _attempts[id] = 0;
    return issue(ticket);
  }

  @override
  Future<void> discard(String ticket) async {
    tickets.remove(ticket);
    _fresh.remove(ticket);
  }
}
