import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/session_vault.dart';
import 'data/auth_gateway.dart';
import 'data/app_pin_gateway.dart';
import 'data/profile_photo.dart';
import 'data/settings_gateway.dart';
import 'telegram_window.dart';
import 'telegram_native.dart';

enum SessionPhase { starting, signedOut, signedIn, storageError, pinLocked }

enum PinStage { none, checking, create, confirm, unlock }

enum AuthScreen { welcome, login, register, email, otp }

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
    this.pinGateway,
    NativeTelegramClient? nativeTelegram,
  }) : nativeTelegram = nativeTelegram ?? NativeTelegramClient(),
       _clock = clock ?? DateTime.now;
  final NativeTelegramClient nativeTelegram;
  final AuthGateway gateway;
  final AppPinGateway? pinGateway;
  final SessionVault vault;
  final DateTime Function() _clock;
  final String deviceType;
  SessionPhase phase = SessionPhase.starting;
  AuthScreen screen = AuthScreen.welcome;
  SessionIdentity? identity;
  ApiFailure? failure;
  String? notice;
  bool busy = false;
  ProfilePhoto? profilePhoto;
  ApiFailure? photoFailure;
  bool photoBusy = false, photoLoaded = false;
  int _photoGeneration = 0;
  ProfilePhotoGateway? get _photos => gateway is HttpAuthGateway
      ? HttpProfilePhotoGateway((gateway as HttpAuthGateway).client)
      : gateway is ProfilePhotoGateway
      ? gateway as ProfilePhotoGateway
      : null;

  Future<void> loadProfilePhoto() async {
    final photos = _photos;
    if (photos == null ||
        photoLoaded ||
        photoBusy ||
        phase != SessionPhase.signedIn) {
      return;
    }
    final generation = ++_photoGeneration;
    final identityId = identity?.userId;
    photoBusy = true;
    photoFailure = null;
    _emit();
    try {
      final photo = await authorizedRead(photos.readPhoto);
      if (!_disposed &&
          generation == _photoGeneration &&
          identity?.userId == identityId) {
        profilePhoto = photo;
        photoLoaded = true;
      }
    } on ApiFailure catch (error) {
      if (!_disposed && generation == _photoGeneration) photoFailure = error;
    } finally {
      if (!_disposed && generation == _photoGeneration) {
        photoBusy = false;
        _emit();
      }
    }
  }

  Future<bool> saveProfilePhoto(Uint8List bytes) async {
    final photos = _photos;
    if (photos == null || photoBusy || phase != SessionPhase.signedIn) {
      return false;
    }
    final generation = ++_photoGeneration;
    final identityId = identity?.userId;
    photoBusy = true;
    photoFailure = null;
    _emit();
    try {
      final photo = await authorizedMutation(
        (access) => photos.savePhoto(access, bytes),
      );
      if (_disposed ||
          generation != _photoGeneration ||
          identity?.userId != identityId) {
        return false;
      }
      profilePhoto = photo;
      photoLoaded = true;
      return true;
    } on ApiFailure catch (error) {
      if (!_disposed && generation == _photoGeneration) photoFailure = error;
      return false;
    } finally {
      if (!_disposed && generation == _photoGeneration) {
        photoBusy = false;
        _emit();
      }
    }
  }

  PinChallenge? pinChallenge;
  PinStage pinStage = PinStage.none;
  int pinEntryRevision = 0;
  bool pinResetting = false, _recoverPin = false;
  int? _recoveryUserId;
  String? _newPin;
  bool privacyCovered = false, selectingProfilePhoto = false;
  DateTime? _selectionStarted;

  void coverPrivateContent() {
    if (pinChallenge == null ||
        (phase != SessionPhase.signedIn && phase != SessionPhase.pinLocked)) {
      return;
    }
    privacyCovered = true;
    _emit();
  }

  void beginPhotoSelection() {
    beginTrustedImageSelection();
  }

  void beginTrustedImageSelection() {
    if (phase != SessionPhase.signedIn || selectingProfilePhoto) return;
    selectingProfilePhoto = true;
    _selectionStarted = _clock();
  }

  void endPhotoSelection() {
    endTrustedImageSelection();
  }

  void endTrustedImageSelection() {
    selectingProfilePhoto = false;
    if (_selectionStarted != null &&
        _clock().difference(_selectionStarted!).inSeconds > 60) {
      lockApp();
    }
    _selectionStarted = null;
  }

  bool get trustedPhotoSelection =>
      selectingProfilePhoto &&
      _selectionStarted != null &&
      _clock().difference(_selectionStarted!).inSeconds <= 60;
  bool get trustedImageSelection => trustedPhotoSelection;
  void uncoverPrivateContent() {
    privacyCovered = false;
    _emit();
  }

  Future<void> _preparePin(
    TokenPair pair,
    SessionIdentity profile,
    int generation,
  ) async {
    phase = SessionPhase.pinLocked;
    pinStage = PinStage.checking;
    identity = profile;
    _emit();
    try {
      final challenge = await pinGateway!.prepare(pair.accessToken);
      if (!_current(generation)) throw _StaleOperation();
      await _storage(() async {
        if (!_current(generation)) throw _StaleOperation();
        await vault.writeRefreshToken(challenge.encode());
      });
      if (!_current(generation)) throw _StaleOperation();
      pinChallenge = challenge;
      pinResetting =
          _recoverPin &&
          challenge.canRecover &&
          challenge.userId == _recoveryUserId;
      pinStage = !challenge.configured || pinResetting
          ? PinStage.create
          : PinStage.unlock;
      _recoverPin = false;
      _newPin = null;
      _tokens = null;
      _refreshToken = null;
      _accessUntil = null;
      failure = null;
      notice = null;
    } catch (_) {
      if (_current(generation)) {
        _forget();
        phase = SessionPhase.signedOut;
        screen = AuthScreen.welcome;
      }
      rethrow;
    }
  }

  Future<void> restorePinStatus() async {
    final cached = pinChallenge;
    if (cached == null || pinGateway == null || busy) return;
    final generation = _generation;
    busy = true;
    failure = null;
    _emit();
    try {
      final status = await pinGateway!.status(cached.ticket);
      if (!_current(generation)) return;
      pinChallenge = status;
      pinStage = status.configured ? PinStage.unlock : PinStage.create;
      await _storage(() async {
        if (_current(generation)) {
          await vault.writeRefreshToken(status.encode());
        }
      });
    } on ApiFailure catch (error) {
      if (_current(generation)) {
        if (error.status == 401) {
          await _invalidate(generation, error.message);
        } else {
          failure = error;
          pinStage = cached.configured ? PinStage.unlock : PinStage.create;
        }
      }
    } on _StorageFailure {
      if (_current(generation)) _storageFailed();
    } finally {
      if (_current(generation)) {
        busy = false;
        _emit();
      }
    }
  }

  void restartPinSetup() {
    if (busy || phase != SessionPhase.pinLocked) return;
    _newPin = null;
    failure = null;
    pinStage = PinStage.create;
    _emit();
  }

  Future<bool> submitPin(String value) async {
    if (pinGateway == null ||
        busy ||
        phase != SessionPhase.pinLocked ||
        !RegExp(r'^[0-9]{4}$').hasMatch(value)) {
      return false;
    }
    final challenge = pinChallenge;
    if (challenge == null) return false;
    failure = null;
    if (pinStage == PinStage.create) {
      _newPin = value;
      pinStage = PinStage.confirm;
      _emit();
      return true;
    }
    if (pinStage == PinStage.confirm && value != _newPin) {
      failure = const ApiFailure(
        'PIN_CONFIRMATION_MISMATCH',
        'The PINs do not match. Try confirming again.',
      );
      _emit();
      return false;
    }
    if (pinStage == PinStage.unlock && challenge.recoveryRequired) {
      failure = const ApiFailure(
        'PIN_RECOVERY_REQUIRED',
        'Five incorrect attempts. Verify your identity to reset your PIN.',
      );
      _emit();
      return false;
    }
    final generation = _generation;
    final confirming = pinStage == PinStage.confirm;
    busy = true;
    _emit();
    try {
      final pair = confirming
          ? await pinGateway!.setup(
              challenge.ticket,
              _newPin!,
              value,
              reset: pinResetting,
            )
          : await pinGateway!.unlock(challenge.ticket, value);
      if (!_current(generation)) return false;
      pinChallenge = PinChallenge(
        ticket: challenge.ticket,
        userId: challenge.userId,
        configured: true,
        attemptsRemaining: 5,
        recoveryRequired: false,
        canRecover: false,
        displayName: challenge.displayName,
      );
      _newPin = null;
      await _install(pair, generation);
      if (!_current(generation)) return false;
      pinStage = PinStage.none;
      pinResetting = false;
      return true;
    } on ApiFailure catch (error) {
      if (!_current(generation)) return false;
      failure = error;
      if (error.code == 'PIN_RECOVERY_AUTH_REQUIRED') {
        final recovering = pinResetting;
        await signOut();
        _recoverPin = recovering;
        _recoveryUserId = challenge.userId;
        if (!_disposed && phase == SessionPhase.signedOut) {
          notice = 'Verify your email or Telegram before creating or resetting your PIN.';
          _emit();
        }
        return false;
      }
      if (error.code == 'PIN_RECOVERY_REQUIRED') {
        pinChallenge = PinChallenge(
          ticket: challenge.ticket,
          userId: challenge.userId,
          configured: true,
          attemptsRemaining: 0,
          recoveryRequired: true,
          canRecover: challenge.canRecover,
          displayName: challenge.displayName,
        );
      }
      if (error.status == 401) {
        await _invalidate(generation, error.message);
        return false;
      }
      try {
        final status = await pinGateway!.status(challenge.ticket);
        if (_current(generation)) {
          pinChallenge = status;
          // A lost setup response is resolved by a fresh, explicit PIN entry.
          if (confirming &&
              status.configured &&
              error.code != 'PIN_CONFIRMATION_MISMATCH') {
            _newPin = null;
            pinStage = PinStage.unlock;
          }
        }
      } on ApiFailure catch (_) {
        /* Keep the gate closed and retain the ticket. */
      }
      return false;
    } on _StorageFailure {
      if (_current(generation)) _storageFailed();
      return false;
    } on _StaleOperation {
      return false;
    } finally {
      if (_current(generation)) {
        busy = false;
        _emit();
      }
    }
  }

  /// One PIN covers foreground use until idle. Normal background visits lock immediately.
  /// Transfers still ask for the PIN every time.
  static const idleLimit = Duration(minutes: 3);
  DateTime? _lastActivity, _backgroundedAt;

  void noteActivity() {
    if (phase == SessionPhase.signedIn) _lastActivity = _clock();
  }

  /// Called periodically; locks after [idleLimit] without interaction.
  void checkIdle() {
    if (phase != SessionPhase.signedIn || trustedImageSelection) return;
    final last = _lastActivity ??= _clock();
    if (_clock().difference(last) >= idleLimit) lockApp();
  }

  void markBackground() {
    // Keep the first departure: returning also passes through `hidden`.
    if (phase == SessionPhase.signedIn) _backgroundedAt ??= _clock();
    if (phase == SessionPhase.pinLocked) {
      ++_generation;
      busy = false;
      // A partly typed PIN never survives leaving the app.
      ++pinEntryRevision;
      _emit();
    }
  }

  /// Every normal background visit requires unlocking again on return.
  void markForeground() {
    if (phase == SessionPhase.pinLocked) {
      unawaited(restorePinStatus());
      return;
    }
    final away = _backgroundedAt;
    _backgroundedAt = null;
    if (away == null || phase != SessionPhase.signedIn) return;
    if (!trustedImageSelection) {
      lockApp();
    } else {
      noteActivity();
    }
  }

  void lockApp() {
    if (pinGateway == null || pinChallenge == null || _disposed) return;
    _lastActivity = null;
    _backgroundedAt = null;
    ++_generation;
    ++pinEntryRevision;
    ++_photoGeneration;
    photoBusy = false;
    photoLoaded = false;
    photoFailure = null;
    phase = SessionPhase.pinLocked;
    pinStage = pinChallenge!.configured ? PinStage.unlock : PinStage.create;
    _newPin = null;
    _tokens = null;
    _refreshToken = null;
    _accessUntil = null;
    busy = false;
    failure = null;
    _emit();
    unawaited(restorePinStatus());
  }

  Future<void> forgotPin() async {
    if (busy || phase != SessionPhase.pinLocked) return;
    if (pinChallenge?.canRecover == true) {
      pinResetting = true;
      _newPin = null;
      failure = null;
      pinStage = PinStage.create;
      _emit();
      return;
    }
    final recoveryUser = pinChallenge?.userId;
    await signOut();
    _recoverPin = true;
    _recoveryUserId = recoveryUser;
    if (!_disposed && phase == SessionPhase.signedOut) {
      notice = 'Verify your email or Telegram to reset your PIN.';
      _emit();
    }
  }

  bool registering = false;
  bool _unifiedEmail = false, _linkingEmail = false;
  bool telegramPending = false;
  TelegramWindow? _telegramWindow;
  bool get linkingEmail => _linkingEmail;
  ContinuationGateway get _continuation {
    final candidate = gateway;
    if (candidate is ContinuationGateway) {
      return candidate as ContinuationGateway;
    }
    throw const ApiFailure(
      'AUTH_UNAVAILABLE',
      'This authentication method is unavailable.',
    );
  }

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
      } else if (saved.startsWith('kesor-pin-v1:')) {
        if (pinGateway == null) {
          await _storage(() => vault.writeRefreshToken(null));
          phase = SessionPhase.signedOut;
        } else {
          try {
            pinChallenge = PinChallenge.decode(saved);
          } catch (_) {
            await _storage(() => vault.writeRefreshToken(null));
            phase = SessionPhase.signedOut;
            return;
          }
          phase = SessionPhase.pinLocked;
          pinStage = pinChallenge!.configured
              ? PinStage.unlock
              : PinStage.create;
          busy = false;
          await restorePinStatus();
        }
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
    if (_unifiedEmail) {
      if (screen == AuthScreen.otp) {
        screen = AuthScreen.email;
      } else {
        screen = AuthScreen.welcome;
        _linkingEmail = false;
        _unifiedEmail = false;
      }
      _emit();
      return;
    }
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
      final receipt = _unifiedEmail
          ? (_linkingEmail
                ? await authorizedMutation(
                    (access) => _continuation.requestContinueOtp(
                      draft.email,
                      linkToken: access,
                    ),
                  )
                : await _continuation.requestContinueOtp(draft.email))
          : await gateway.requestOtp(
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
      final payload = <String, dynamic>{
        if (draft.register) 'username': draft.username,
        draft.register ? 'email' : 'usernameOrEmail': draft.email,
        'password': draft.password,
        'otpCode': code,
        'deviceFingerprint': draft.deviceId,
        'deviceName': 'Digital Banking $deviceType',
        'deviceType': deviceType,
      };
      final TokenPair tokens;
      if (_unifiedEmail) {
        payload['email'] = draft.email;
        payload.remove('password');
        payload.remove('usernameOrEmail');
        tokens = _linkingEmail
            ? await _continuation.verifyEmail(
                payload,
                linkToken: await authorizedRead((access) async => access),
              )
            : await _continuation.verifyEmail(payload);
      } else {
        tokens = await gateway.authenticate(payload, register: draft.register);
      }
      await _install(tokens, generation);
      if (_current(generation)) {
        _draft = null;
        _unifiedEmail = false;
        _linkingEmail = false;
        screen = AuthScreen.welcome;
      }
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
      if (pinGateway != null &&
          profile.profileComplete &&
          pinChallenge == null) {
        await _preparePin(pair, profile, generation);
        return;
      }
      await _storage(() async {
        if (!_current(generation)) throw _StaleOperation();
        await vault.writeRefreshToken(
          pinChallenge?.encode() ?? pair.refreshToken,
        );
      });
      if (!_current(generation)) throw _StaleOperation();
      _tokens = pair;
      _accessUntil = _clock().add(Duration(milliseconds: pair.expiresInMs));
      _refreshToken = pair.refreshToken;
      if (identity?.userId != profile.userId) {
        ++_photoGeneration;
        profilePhoto = null;
        photoFailure = null;
        photoBusy = false;
        photoLoaded = false;
      }
      identity = profile;
      phase = SessionPhase.signedIn;
      failure = null;
      notice = null;
    } catch (_) {
      if (!(phase == SessionPhase.pinLocked && pinChallenge != null)) {
        await _logoutQuietly(pair.accessToken);
      }
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
        if (pinChallenge == null) await vault.writeRefreshToken(null);
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

  /// Coordinated refresh and at most one retry, exclusively for safe reads.
  Future<T> authorizedRead<T>(Future<T> Function(String token) action) =>
      _authorized(action, retryRead: true);

  /// Preflight renewal is safe; once sent, a mutation is never replayed.
  Future<T> authorizedMutation<T>(Future<T> Function(String token) action) =>
      _authorized(action, retryRead: false);

  Future<T> _authorized<T>(
    Future<T> Function(String token) action, {
    required bool retryRead,
  }) async {
    if (phase == SessionPhase.pinLocked) {
      throw const ApiFailure(
        'PIN_REQUIRED',
        'Unlock the app with your PIN.',
        status: 403,
      );
    }
    final generation = _generation;
    try {
      if (_tokens == null) {
        throw const ApiFailure('SESSION_INVALID', 'Please sign in again.');
      }
      if (_refreshing != null || !(_accessUntil?.isAfter(_clock()) ?? false)) {
        await _refresh(generation);
      }
      if (!_current(generation)) throw _StaleOperation();
      T result;
      final attemptedAccess = _tokens!.accessToken;
      try {
        result = await action(attemptedAccess);
      } on ApiFailure catch (e) {
        if (!retryRead || e.status != 401 || e.code != 'TOKEN_INVALID') rethrow;
        if (!_current(generation)) throw _StaleOperation();
        // Another read may already have renewed the token while this response was in flight.
        if (_tokens?.accessToken == attemptedAccess) await _refresh(generation);
        if (!_current(generation)) throw _StaleOperation();
        result = await action(_tokens!.accessToken);
      }
      if (!_current(generation)) throw _StaleOperation();
      return result;
    } on _StorageFailure {
      throw const ApiFailure(
        'STORAGE_UNAVAILABLE',
        'Secure storage is unavailable. Please sign in again.',
      );
    } on _StaleOperation {
      throw const ApiFailure('SESSION_CHANGED', 'Your session has changed.');
    } on ApiFailure catch (e) {
      if (_current(generation) && e.status == 401) {
        await _invalidate(generation, e.message);
      }
      rethrow;
    }
  }

  Future<SessionIdentity> checkIdentity() async {
    final generation = _generation;
    final profile = await authorizedRead(gateway.me);
    if (!_current(generation)) {
      throw const ApiFailure('SESSION_CHANGED', 'Your session has changed.');
    }
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
  }

  Future<void> refreshProfile() async {
    if (busy || phase != SessionPhase.signedIn) return;
    final generation = _generation;
    busy = true;
    failure = null;
    notice = null;
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
    if (_disposed ||
        (phase != SessionPhase.signedIn && phase != SessionPhase.pinLocked)) {
      return;
    }
    final pinTicket = pinChallenge?.ticket;
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
    if (pinTicket != null && pinGateway != null) {
      try {
        await pinGateway!.discard(pinTicket);
        revoked = true;
      } catch (_) {
        /* Local logout still completes. */
      }
    }
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
      screen = _unifiedEmail
          ? AuthScreen.email
          : registering
          ? AuthScreen.register
          : AuthScreen.login;
      failure = null;
      notice = 'For your privacy, enter your details again to continue.';
      _emit();
    }
  }

  void _forget() {
    pinChallenge = null;
    pinStage = PinStage.none;
    _newPin = null;
    pinResetting = false;
    privacyCovered = false;
    selectingProfilePhoto = false;
    _selectionStarted = null;
    ++_photoGeneration;
    profilePhoto = null;
    photoFailure = null;
    photoBusy = false;
    photoLoaded = false;
    _telegramWindow?.close();
    unawaited(nativeTelegram.cancel());
    _telegramWindow = null;
    telegramPending = false;
    _unifiedEmail = false;
    _linkingEmail = false;
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

  void openEmail({bool link = false}) {
    if (busy ||
        (link
            ? phase != SessionPhase.signedIn
            : phase != SessionPhase.signedOut)) {
      return;
    }
    _unifiedEmail = true;
    _linkingEmail = link;
    registering = false;
    _draft = null;
    failure = null;
    notice = null;
    screen = AuthScreen.email;
    _emit();
  }

  Future<bool> beginEmail(String email) async {
    if (busy) return false;
    final generation = ++_generation;
    busy = true;
    failure = null;
    notice = null;
    _draft = null;
    _unifiedEmail = true;
    _emit();
    try {
      final device = await _storage(vault.installationId);
      if (!_current(generation)) return false;
      final normalized = email.trim().toLowerCase();
      final receipt = _linkingEmail
          ? await authorizedMutation(
              (access) => _continuation.requestContinueOtp(
                normalized,
                linkToken: access,
              ),
            )
          : await _continuation.requestContinueOtp(normalized);
      if (!_current(generation)) return false;
      _draft = _Draft(normalized, '', null, device, false);
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

  Future<void> completeInformation(String first, String last) async {
    if (busy || phase != SessionPhase.signedIn) return;
    final generation = _generation;
    busy = true;
    failure = null;
    _emit();
    try {
      final profile = await authorizedMutation(
        (access) =>
            _continuation.completeProfile(access, first.trim(), last.trim()),
      );
      if (_current(generation)) {
        identity = profile;
        screen = AuthScreen.welcome;
        if (pinGateway != null && _tokens != null) {
          await _preparePin(_tokens!, profile, generation);
        }
      }
    } on _StorageFailure {
      if (_current(generation)) _storageFailed();
    } on _StaleOperation {
      /* A background lock superseded onboarding. */
    } on ApiFailure catch (e) {
      if (_current(generation)) failure = e;
    } finally {
      if (_current(generation)) {
        busy = false;
        _emit();
      }
    }
  }

  Future<bool> updateProfileDetails(String first, String last) async {
    if (busy || phase != SessionPhase.signedIn) return false;
    final generation = _generation;
    busy = true;
    failure = null;
    _emit();
    try {
      final updated = await authorizedMutation(
        (token) =>
            SettingsGateway(gateway)
                .updateProfile(token, first.trim(), last.trim()),
      );
      if (!_current(generation)) return false;
      identity = updated;
      return true;
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

  Future<bool> changePin(String current, String pin, String confirm) async {
    if (busy || phase != SessionPhase.signedIn) return false;
    final changer = pinGateway;
    if (changer is! PinChangeGateway) {
      failure = const ApiFailure(
        'PIN_UNAVAILABLE',
        'PIN changes require the configured app lock.',
      );
      _emit();
      return false;
    }
    final generation = _generation;
    busy = true;
    failure = null;
    _emit();
    try {
      await authorizedMutation(
        (token) =>
            (changer as PinChangeGateway).change(token, current, pin, confirm),
      );
      return _current(generation);
    } on ApiFailure catch (e) {
      if (_current(generation)) {
        failure = e;
        if (e.code == 'PIN_RECOVERY_REQUIRED' || e.code == 'PIN_REQUIRED') {
          lockApp();
        }
      }
    } finally {
      if (_current(generation)) {
        busy = false;
        _emit();
      }
    }
    return false;
  }

  Future<void> continueTelegram() async {
    if (busy) return;
    if (nativeTelegram.supported) return _continueNativeTelegram();
    final generation = ++_generation;
    final linking = phase == SessionPhase.signedIn;
    final popup = TelegramWindow();
    if (!popup.available) {
      popup.close();
      failure = const ApiFailure(
        'POPUP_BLOCKED',
        'Allow the Telegram login popup in your browser, then try again. Browser login is required for Telegram.',
      );
      _emit();
      return;
    }
    _telegramWindow = popup;
    busy = true;
    telegramPending = true;
    failure = null;
    notice = null;
    _emit();
    try {
      final installation = await _storage(vault.installationId);
      if (!_current(generation)) return;
      final device = <String, dynamic>{
        'deviceFingerprint': installation,
        'deviceName': 'Kesor Bank $deviceType',
        'deviceType': deviceType,
      };
      final start = linking
          ? await authorizedMutation(
              (access) =>
                  _continuation.startTelegram(device, linkToken: access),
            )
          : await _continuation.startTelegram(device);
      if (!_current(generation)) return;
      popup.configure(
        start['flowId'] as String,
        start['callbackOrigin'] as String,
      );
      popup.navigate(start['authorizationUrl'] as String);
      final until = _clock().add(
        Duration(seconds: (start['expiresInSeconds'] as int).clamp(1, 300)),
      );
      while (_current(generation) && _clock().isBefore(until)) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!_current(generation)) return;
        if (popup.approvalReceipt == null) continue;
        final result = await _continuation.exchangeTelegram(
          start['flowId'] as String,
          start['exchangeSecret'] as String,
          approvalReceipt: popup.approvalReceipt,
        );
        if (!_current(generation)) {
          if (result['status'] == 'COMPLETE') {
            final latePair = TokenPair.fromJson(
              Map<String, dynamic>.from(result['tokens'] as Map),
            );
            await _logoutQuietly(latePair.accessToken);
          }
          return;
        }
        if (result['status'] == 'PENDING') continue;
        if (result['status'] != 'COMPLETE') {
          throw ApiFailure(
            result['status'] as String,
            ApiFailure.messageFor(result['status'] as String),
          );
        }
        await _install(
          TokenPair.fromJson(
            Map<String, dynamic>.from(result['tokens'] as Map),
          ),
          generation,
        );
        return;
      }
      if (_current(generation)) {
        throw const ApiFailure(
          'TELEGRAM_FLOW_INVALID',
          'Telegram approval timed out. Please try again.',
        );
      }
    } on _StorageFailure {
      if (_current(generation)) _storageFailed();
    } on ApiFailure catch (e) {
      if (_current(generation)) failure = e;
    } catch (_) {
      if (_current(generation)) {
        failure = const ApiFailure(
          'TELEGRAM_REJECTED',
          'Telegram approval could not be completed. Try again or continue with email.',
        );
      }
    } finally {
      popup.close();
      if (_current(generation)) {
        _telegramWindow = null;
        busy = false;
        telegramPending = false;
        _emit();
      }
    }
  }

  Future<void> _continueNativeTelegram() async {
    final generation = ++_generation;
    final linking = phase == SessionPhase.signedIn;
    busy = true;
    telegramPending = true;
    failure = null;
    notice = null;
    _emit();
    try {
      final candidate = gateway;
      if (candidate is! NativeTelegramGateway) {
        throw const ApiFailure(
          'TELEGRAM_UNAVAILABLE',
          'Telegram login requires an API connection.',
        );
      }
      final nativeGateway = candidate as NativeTelegramGateway;
      final installation = await _storage(vault.installationId);
      if (!_current(generation)) return;
      final device = <String, dynamic>{
        'deviceFingerprint': installation,
        'deviceName': 'Kesor Bank Android',
        'deviceType': 'ANDROID',
      };
      final start = linking
          ? await authorizedMutation(
              (access) =>
                  nativeGateway.startNativeTelegram(device, linkToken: access),
            )
          : await nativeGateway.startNativeTelegram(device);
      if (!_current(generation)) return;
      final flowId = start['flowId'] as String;
      final exchangeSecret = start['exchangeSecret'] as String;
      final code = await nativeTelegram
          .authorize(
            authorizationUrl: start['authorizationUrl'] as String,
            redirectUri: start['redirectUri'] as String,
            flowId: flowId,
          )
          .timeout(
            Duration(seconds: (start['expiresInSeconds'] as int).clamp(1, 300)),
          );
      if (!_current(generation)) return;
      // Exactly one request: on an uncertain outcome, begin a fresh approval.
      final pair = await nativeGateway.exchangeNativeTelegram(
        flowId,
        exchangeSecret,
        code,
      );
      if (!_current(generation)) {
        await _logoutQuietly(pair.accessToken);
        return;
      }
      await _install(pair, generation);
    } on _StorageFailure {
      if (_current(generation)) _storageFailed();
    } on ApiFailure catch (error) {
      if (_current(generation)) failure = error;
    } on TimeoutException {
      if (_current(generation)) {
        failure = ApiFailure(
          'TELEGRAM_FLOW_INVALID',
          ApiFailure.messageFor('TELEGRAM_FLOW_INVALID'),
        );
      }
    } on _StaleOperation {
      // Sign-out or disposal superseded the login response.
    } catch (_) {
      if (_current(generation)) {
        failure = ApiFailure(
          'TELEGRAM_REJECTED',
          ApiFailure.messageFor('TELEGRAM_REJECTED'),
        );
      }
    } finally {
      if (_current(generation)) await nativeTelegram.cancel();
      if (_current(generation)) {
        busy = false;
        telegramPending = false;
        _emit();
      }
    }
  }

  void cancelTelegram() {
    if (!telegramPending) return;
    ++_generation;
    _telegramWindow?.close();
    _telegramWindow = null;
    unawaited(nativeTelegram.cancel());
    busy = false;
    telegramPending = false;
    failure = null;
    notice = 'Telegram approval cancelled.';
    _emit();
  }
}
