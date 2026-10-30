import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/network/api_client.dart';
import '../auth/session_controller.dart';
import 'account_gateway.dart';

class PairOpeningRequest {
  const PairOpeningRequest(this.key, this.type);
  factory PairOpeningRequest.create(String type) => PairOpeningRequest(
    'pair-${List.generate(24, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}',
    type,
  );
  factory PairOpeningRequest.fromJson(Object? value) {
    final data = objectData(value);
    final key = textField(data, 'key'), type = textField(data, 'type');
    if (data['version'] != 1 ||
        !BankAccount.types.contains(type) ||
        !RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(key)) {
      throw invalidAccountData;
    }
    return PairOpeningRequest(key, type);
  }
  final String key, type;
  Map<String, dynamic> toJson() => {'version': 1, 'key': key, 'type': type};
}

/// Separate namespace: legacy uncertain single-account markers are never reinterpreted.
class PairOpeningStore {
  PairOpeningStore({String? namespace, FlutterSecureStorage? storage})
    : _prefix = namespace == null
          ? null
          : 'banking.pairs.${base64Url.encode(utf8.encode(namespace))}',
      _storage = storage ?? const FlutterSecureStorage();
  final String? _prefix;
  final FlutterSecureStorage _storage;
  final Map<int, PairOpeningRequest> _memory = {};
  static final Map<String, Future<void>> _tails = {};
  Future<T> _serial<T>(int user, Future<T> Function(String?) work) {
    final key = _prefix == null ? null : '$_prefix.$user';
    final lockKey = key ?? 'memory-${identityHashCode(this)}.$user';
    final result = (_tails[lockKey] ?? Future<void>.value()).then(
      (_) => work(key),
    );
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tails[lockKey] = tail;
    tail.then((_) {
      if (identical(_tails[lockKey], tail)) _tails.remove(lockKey);
    });
    return result;
  }

  Future<PairOpeningRequest?> _read(int user, String? key) async {
    if (key == null) return _memory[user];
    final raw = await _storage.read(key: key);
    return raw == null ? null : PairOpeningRequest.fromJson(jsonDecode(raw));
  }

  Future<PairOpeningRequest?> read(int user) =>
      _serial(user, (key) => _read(user, key));
  Future<void> claim(int user, PairOpeningRequest request) =>
      _serial(user, (key) async {
        if (await _read(user, key) != null) {
          throw const ApiFailure(
            'OPENING_PENDING',
            'An account-opening request needs attention.',
          );
        }
        if (key == null) {
          _memory[user] = request;
        } else {
          await _storage.write(key: key, value: jsonEncode(request.toJson()));
        }
      });
  Future<void> clear(int user, PairOpeningRequest request) =>
      _serial(user, (key) async {
        final saved = await _read(user, key);
        if (saved?.key != request.key || saved?.type != request.type) {
          throw invalidAccountData;
        }
        if (key == null) {
          _memory.remove(user);
        } else {
          await _storage.delete(key: key);
        }
      });
}

class PairOpeningController extends ChangeNotifier {
  PairOpeningController(
    this.session,
    this.gateway,
    this.store, {
    required this.onSuccess,
  }) : _user = session.identity!.userId,
       _session = session.identity!.sessionId {
    session.addListener(_sessionChanged);
  }
  final SessionController session;
  final AccountPairGateway gateway;
  final PairOpeningStore store;
  final Future<void> Function() onSuccess;
  final int _user;
  final String _session;
  bool _disposed = false, _active = true;
  bool ready = false, busy = false;
  OpeningPolicy? policy;
  PairOpeningRequest? pending;
  AccountPairResult? result;
  ApiFailure? error;
  bool get _current =>
      !_disposed &&
      _active &&
      session.phase == SessionPhase.signedIn &&
      session.identity?.userId == _user &&
      session.identity?.sessionId == _session;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _sessionChanged() {
    if (!_current && _active) {
      _active = false;
      policy = null;
      pending = null;
      result = null;
      error = null;
      ready = busy = false;
      _emit();
    }
  }

  Future<void> initialize() async {
    if (!_current || busy) return;
    busy = true;
    ready = false;
    error = null;
    _emit();
    try {
      final saved = await store.read(_user);
      if (!_current) return;
      pending = saved;
      final next = await session.authorizedRead(gateway.openingPolicy);
      if (!_current) return;
      policy = next;
      ready = true;
    } catch (e) {
      if (_current) {
        error = e is ApiFailure
            ? e
            : const ApiFailure(
                'OPENING_STORAGE',
                'Account-opening safety could not be loaded.',
              );
      }
    } finally {
      if (_current) {
        busy = false;
        _emit();
      }
    }
  }

  Future<bool> open(String type) async {
    if (!_current ||
        !ready ||
        busy ||
        pending != null ||
        !BankAccount.types.contains(type)) {
      return false;
    }
    busy = true;
    error = null;
    result = null;
    _emit();
    try {
      final request = PairOpeningRequest.create(type);
      await store.claim(_user, request);
      if (!_current) return false;
      pending = request;
      return await _send(request);
    } catch (e) {
      if (_current) {
        ready = false;
        error = const ApiFailure(
          'OPENING_STORAGE',
          'Account-opening safety could not be saved.',
        );
      }
      return false;
    } finally {
      if (_current) {
        busy = false;
        _emit();
      }
    }
  }

  Future<bool> retry() async {
    if (!_current || !ready || busy || pending == null) return false;
    busy = true;
    error = null;
    _emit();
    try {
      final saved = await store.read(_user);
      if (!_current) return false;
      if (saved?.key != pending!.key || saved?.type != pending!.type) {
        throw invalidAccountData;
      }
      return await _send(saved!);
    } catch (e) {
      if (_current) {
        ready = false;
        error = const ApiFailure(
          'OPENING_STORAGE',
          'The saved account-opening request could not be verified.',
        );
      }
      return false;
    } finally {
      if (_current) {
        busy = false;
        _emit();
      }
    }
  }

  Future<bool> _send(PairOpeningRequest request) async {
    try {
      final response = await session.authorizedMutation(
        (token) => gateway.openPair(token, request.type, request.key),
      );
      if (!_current) return false;
      await store.clear(_user, request);
      if (!_current) return false;
      pending = null;
      result = response;
      try {
        await onSuccess();
      } catch (_) {
        if (_current) {
          error = const ApiFailure(
            'REFRESH_FAILED',
            'Accounts opened. Refresh to obtain current balances.',
          );
        }
      }
      return true;
    } on ApiFailure catch (e) {
      if (!_current) return false;
      error = e;
      // Only validation/authorization rejections establish that nothing was opened.
      if (e.status != null && {400, 403, 404, 422}.contains(e.status)) {
        await store.clear(_user, request);
        if (_current) pending = null;
      }
      return false;
    }
  }

  @override
  void dispose() {
    session.removeListener(_sessionChanged);
    _disposed = true;
    super.dispose();
  }
}
