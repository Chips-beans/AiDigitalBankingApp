import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/session_vault.dart';
import 'data/auth_gateway.dart';

enum SessionPhase { starting, signedOut, signedIn, storageError }

enum AuthScreen { welcome, login, register, otp }

class _Draft {
  _Draft(
    this.email,
    this.password,
    this.username,
    this.deviceId,
    this.register,
  );
  final String email;
  final String password;
  final String? username;
  final String deviceId;
  final bool register;
}

class _StaleOperation implements Exception {}

class _StorageFailure implements Exception {}

class SessionController extends ChangeNotifier {
  SessionController(
    this.gateway,
    this.vault, {
    DateTime Function()? clock,
    this.deviceType = 'MOBILE',
  }) : _clock = clock ?? DateTime.now;
  final AuthGateway gateway;
  final SessionVault vault;
  final DateTime Function() _clock;
  final String deviceType;
  SessionPhase phase = SessionPhase.starting;
  AuthScreen screen = AuthScreen.welcome;
  SessionIdentity? identity;
  ApiFailure? failure;
  String? notice;
  bool busy = false;
  bool registering = false;
  _Draft? _draft;
  DateTime? _expiresAt, _resendAt, _draftUntil, _accessUntil;
  String? _refreshToken;
  TokenPair? _tokens;
  Future<void>? _refreshing;
  Future<void> _storageTail = Future.value();
  int _generation = 0;
  bool _disposed = false;
  bool _mustClear = false;

  String get otpEmail => _draft?.email ?? '';
  int get resendSeconds => _remaining(_resendAt);
  int get expirySeconds => _remaining(_expiresAt);
  int _remaining(DateTime? time) => time == null
      ? 0
      : ((time.difference(_clock()).inMilliseconds + 999) ~/ 1000).clamp(
          0,
          86400,
        );
  bool _current(int generation) => !_disposed && generation == _generation;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<T> _storage<T>(Future<T> Function() action) {
    final result = _storageTail.then((_) => action());
    _storageTail = result.then<void>(
      (_) {},
      onError: (Object e, StackTrace s) {},
    );
    return result.catchError((Object e) {
      if (e is _StaleOperation) throw e;
      throw _StorageFailure();
    });
  }

  Future<void> initialize() async {
    if (busy || _disposed) return;
    final generation = ++_generation;
    busy = true;
    phase = SessionPhase.starting;
    failure = null;
    _emit();
    try {
      if (_mustClear) await _storage(() => vault.writeRefreshToken(null));
      _mustClear = false;
      final saved = await _storage(vault.readRefreshToken);
      if (!_current(generation)) return;
      if (saved == null || saved.isEmpty) {
        phase = SessionPhase.signedOut;
      } else {
        _refreshToken = saved;
        await _refresh(generation);
      }
    } on _StorageFailure {
      if (_current(generation)) _storageFailed();
    } on ApiFailure catch (e) {
      if (_current(generation) && phase != SessionPhase.storageError) {
        notice = e.message;
      }
    } on _StaleOperation {
      // Logout/disposal superseded this response.
    } finally {
      if (_current(generation)) {
        busy = false;
        _emit();
      }
    }
  }

  void openForm({required bool register}) {
    if (busy || phase != SessionPhase.signedOut) return;
    _draft = null;
    registering = register;
    screen = register ? AuthScreen.register : AuthScreen.login;
    failure = null;
    _emit();
  }

  void back() {
    if (busy) return;
    _draft = null;
    failure = null;
    screen = screen == AuthScreen.otp
        ? (registering ? AuthScreen.register : AuthScreen.login)
        : AuthScreen.welcome;
    _emit();
  }

  Future<bool> begin({
    required String email,
    required String password,
    String? username,
    required bool register,
  }) async {
    if (busy || phase != SessionPhase.signedOut) return false;
    final generation = ++_generation;
    busy = true;
    failure = null;
    notice = null;
    _draft = null;
    _emit();
    try {
      final device = await _storage(vault.installationId);
      if (!_current(generation)) return false;
      final draft = _Draft(
        email.trim().toLowerCase(),
        password,
        username?.trim(),
        device,
        register,
      );
      final receipt = await gateway.requestOtp(
        draft.email,
        register ? 'SIGNUP' : 'LOGIN',
      );
      if (!_current(generation)) return false;
      _draft = draft;
      registering = register;
      _expiresAt = _clock().add(Duration(seconds: receipt.expiresInSeconds));
      _resendAt = _clock().add(Duration(seconds: receipt.resendAfterSeconds));
      _draftUntil = _clock().add(const Duration(minutes: 10));
      screen = AuthScreen.otp;
      return true;
    } on _StorageFailure {
      if (_current(generation)) _storageFailed();
    } on ApiFailure catch (e) {
      if (_current(generation)) failure = e;
    } finally {
      if (_current(generation)) {
        busy = false;
        _emit();
      }
    }
    return false;
  }

  Future<void> resend() async {
    expirePendingIfNeeded();
    final draft = _draft;
    if (draft == null || busy || resendSeconds > 0) return;
    final generation = _generation;
    busy = true;
    failure = null;
    _emit();
    try {
      final receipt = await gateway.requestOtp(
        draft.email,
        draft.register ? 'SIGNUP' : 'LOGIN',
      );
      if (!_current(generation) || _draft != draft) return;
      _expiresAt = _clock().add(Duration(seconds: receipt.expiresInSeconds));
      _resendAt = _clock().add(Duration(seconds: receipt.resendAfterSeconds));
      notice = 'A new code has been requested. Use the latest email.';
    } on ApiFailure catch (e) {
      if (_current(generation)) {
        failure = e;
        if (e.retryAfterSeconds != null) {
          _resendAt = _clock().add(Duration(seconds: e.retryAfterSeconds!));
        }
      }
    } finally {
      if (_current(generation)) {
        busy = false;
        _emit();
      }
    }
  }

  Future<bool> verifyCode(String code) async {
    expirePendingIfNeeded();
    final draft = _draft;
    if (busy || draft == null) return false;
    final generation = _generation;
    busy = true;
    failure = null;
    notice = null;
    _emit();
    try {
      final tokens = await gateway.authenticate({
        if (draft.register) 'username': draft.username,
        draft.register ? 'email' : 'usernameOrEmail': draft.email,
        'password': draft.password,
        'otpCode': code,
        'deviceFingerprint': draft.deviceId,
        'deviceName': 'Digital Banking $deviceType',
        'deviceType': deviceType,
      }, register: draft.register);
      await _install(tokens, generation);
      if (_current(generation)) _draft = null;
      return _current(generation);
    } on _StorageFailure {
      if (_current(generation)) _storageFailed();
    } on ApiFailure catch (e) {
      if (_current(generation)) {
        failure = e;
        if (e.retryAfterSeconds != null) {
          _resendAt = _clock().add(Duration(seconds: e.retryAfterSeconds!));
        }
      }
    } on _StaleOperation {
      // Do not publish a late authentication response.
    } finally {
      if (_current(generation)) {
        busy = false;
        _emit();
      }
    }
    return false;
  }

  Future<void> _install(TokenPair pair, int generation) async {
    try {
      final profile = await gateway.me(pair.accessToken);
      if (!profile.roles.contains('ROLE_CUSTOMER')) {
        throw const ApiFailure(
          'CUSTOMER_REQUIRED',
          'This app is for customer profiles. Sign in with a customer account.',
        );
      }
      if (!_current(generation)) throw _StaleOperation();
      await _storage(() async {
        if (!_current(generation)) throw _StaleOperation();
        await vault.writeRefreshToken(pair.refreshToken);
      });
      if (!_current(generation)) throw _StaleOperation();
      _tokens = pair;
      _accessUntil = _clock().add(Duration(milliseconds: pair.expiresInMs));
      _refreshToken = pair.refreshToken;
      identity = profile;
      phase = SessionPhase.signedIn;
      failure = null;
      notice = null;
    } catch (_) {
      await _logoutQuietly(pair.accessToken);
      rethrow;
    }
  }

  Future<void> _refresh(int generation) {
    final existing = _refreshing;
    if (existing != null) return existing;
    late final Future<void> flight;
    flight = _refreshNow(generation).whenComplete(() {
      if (identical(_refreshing, flight)) _refreshing = null;
    });
    _refreshing = flight;
    return flight;
  }

  Future<void> _refreshNow(int generation) async {
    try {
      final saved = _refreshToken;
      if (saved == null) {
        throw const ApiFailure('SESSION_INVALID', 'Please sign in again.');
      }
      // Consume locally before sending: an uncertain rotating refresh is never replayed.
      await _storage(() async {
        if (!_current(generation)) throw _StaleOperation();
        await vault.writeRefreshToken(null);
      });
      if (!_current(generation)) throw _StaleOperation();
      _refreshToken = null;
      final pair = await gateway.refresh(saved);
      await _install(pair, generation);
    } on _StorageFailure {
      if (_current(generation)) _storageFailed();
      rethrow;
    } on ApiFailure catch (e) {
      if (_current(generation)) {
        await _invalidate(
          generation,
          e.status == 401 ? e.message : 'Your session renewal could not be confirmed. Please sign in again.',
        );
      }
      rethrow;
    }
  }

  /// Shared protected-read entry point for F2 identity and later account repositories.
  Future<SessionIdentity> checkIdentity() async {
    final generation = _generation;
    try {
      if (_tokens == null) {
        throw const ApiFailure('SESSION_INVALID', 'Please sign in again.');
      }
      if (_refreshing != null || !(_accessUntil?.isAfter(_clock()) ?? false)) {
        await _refresh(generation);
      }
      if (!_current(generation)) throw _StaleOperation();
      SessionIdentity profile;
      final attemptedAccess = _tokens!.accessToken;
      try {
        profile = await gateway.me(attemptedAccess);
      } on ApiFailure catch (e) {
        if (e.status != 401 || e.code != 'TOKEN_INVALID') rethrow;
        if (!_current(generation)) throw _StaleOperation();
        // Another read may already have renewed the token while this response was in flight.
        if (_tokens?.accessToken == attemptedAccess) await _refresh(generation);
        if (!_current(generation)) throw _StaleOperation();
        profile = await gateway.me(_tokens!.accessToken);
      }
      if (!_current(generation)) throw _StaleOperation();
      if (!profile.roles.contains('ROLE_CUSTOMER')) {
        await signOut();
        throw const ApiFailure(
          'CUSTOMER_REQUIRED',
          'This app requires a customer profile.',
        );
      }
      identity = profile;
      _emit();
      return profile;
    } on ApiFailure catch (e) {
      if (_current(generation) && e.status == 401) {
        await _invalidate(generation, e.message);
      }
      rethrow;
    }
  }

  Future<void> refreshProfile() async {
    if (busy || phase != SessionPhase.signedIn) return;
    final generation = _generation;
    busy = true;
    failure = null;
    _emit();
    try {
      await checkIdentity();
      if (_current(generation) && phase == SessionPhase.signedIn) {
        notice = 'Your profile is up to date.';
      }
    } on ApiFailure catch (e) {
      if (_current(generation)) failure = e;
    } on _StorageFailure {
      if (_current(generation)) _storageFailed();
    } on _StaleOperation {
      /* Superseded. */
    } finally {
      if (_current(generation)) {
        busy = false;
        _emit();
      }
    }
  }

  Future<void> _invalidate(int generation, String message) async {
    if (!_current(generation)) return;
    final invalidatedGeneration = ++_generation;
    busy = false;
    _forget();
    phase = SessionPhase.signedOut;
    screen = AuthScreen.welcome;
    notice = message;
    _emit();
    try {
      await _storage(() async {
        if (_current(invalidatedGeneration)) {
          await vault.writeRefreshToken(null);
        }
      });
    } on _StorageFailure {
      if (_current(invalidatedGeneration)) _storageFailed();
    }
  }

  Future<void> signOut() async {
    if (_disposed || phase != SessionPhase.signedIn) return;
    final pair = _tokens;
    final saved = _refreshToken;
    final pendingRefresh = _refreshing;
    final generation = ++_generation;
    busy = true;
    _forget();
    screen = AuthScreen.welcome;
    phase = SessionPhase.signedOut;
    failure = null;
    notice = null;
    _emit(); // Hide private content before storage/network operations finish.
    bool storageOk = true;
    try {
      await _storage(() => vault.writeRefreshToken(null));
    } on _StorageFailure {
      storageOk = false;
      _storageFailed();
    }
    bool revoked = false;
    if (pendingRefresh != null) {
      try {
        await pendingRefresh;
        revoked = true;
      } catch (_) {
        /* Late result revokes itself where possible. */
      }
    }
    if (pair != null && !revoked) {
      revoked = await _logoutQuietly(pair.accessToken);
    }
    if (!revoked && pendingRefresh == null && saved != null) {
      try {
        final renewed = await gateway.refresh(saved);
        revoked = await _logoutQuietly(renewed.accessToken);
      } catch (_) {
        /* Local logout still completes. */
      }
    }
    if (_current(generation)) {
      if (storageOk) notice = revoked ? 'You have signed out.' : 'Signed out on this device. Server sign-out could not be confirmed.';
      busy = false;
      _emit();
    }
  }

  Future<bool> _logoutQuietly(String access) async {
    try {
      await gateway.logout(access);
      return true;
    } catch (_) {
      return false;
    }
  }

  void expirePendingIfNeeded() {
    if (_draft != null && !busy && !(_draftUntil?.isAfter(_clock()) ?? false)) {
      _draft = null;
      screen = registering ? AuthScreen.register : AuthScreen.login;
      failure = null;
      notice = 'For your privacy, enter your details again to continue.';
      _emit();
    }
  }

  void _forget() {
    identity = null;
    _tokens = null;
    _refreshToken = null;
    _draft = null;
    _accessUntil = null;
  }

  void _storageFailed() {
    ++_generation;
    busy = false;
    _forget();
    _mustClear = true;
    phase = SessionPhase.storageError;
    screen = AuthScreen.welcome;
    failure = null;
    notice = 'Secure storage is unavailable. Retry to safely clear the saved session before continuing.';
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _forget();
    super.dispose();
  }
}
