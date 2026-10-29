import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Only an uncertainty flag is persisted; no accounts, balances or tokens.
abstract interface class CreationStore {
  Future<bool> pending(int userId);
  Future<void> setPending(int userId, bool value);
}

class SecureCreationStore implements CreationStore {
  SecureCreationStore(String namespace, {FlutterSecureStorage? storage})
    : _prefix = 'banking.f3.${base64Url.encode(utf8.encode(namespace))}',
      _storage = storage ?? const FlutterSecureStorage();
  final String _prefix;
  final FlutterSecureStorage _storage;
  static final Map<String, Future<void>> _tails = {};
  Future<T> _serial<T>(int userId, Future<T> Function(String key) action) {
    final key = '$_prefix.$userId.opening';
    final result = (_tails[key] ?? Future<void>.value()).then(
      (_) => action(key),
    );
    final tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    _tails[key] = tail;
    tail.then((_) {
      if (identical(_tails[key], tail)) _tails.remove(key);
    });
    return result;
  }

  @override
  Future<bool> pending(int userId) =>
      _serial(userId, (key) async => await _storage.read(key: key) != null);
  @override
  Future<void> setPending(int userId, bool value) => _serial(
    userId,
    (key) => value
        ? _storage.write(key: key, value: 'uncertain')
        : _storage.delete(key: key),
  );
}

class MemoryCreationStore implements CreationStore {
  final Set<int> _pending = {};
  @override
  Future<bool> pending(int userId) async => _pending.contains(userId);
  @override
  Future<void> setPending(int userId, bool value) async {
    if (value) {
      _pending.add(userId);
    } else {
      _pending.remove(userId);
    }
  }
}
