import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/network/api_client.dart';
import 'transfer_models.dart';

abstract interface class TransferStore {
  Future<SavedTransfer?> read(int user);
  Future<void> claim(int user, SavedTransfer record);
  Future<void> resolve(int user, SavedTransfer record);
  Future<void> dismiss(int user, String key);
}

const pendingTransfer = ApiFailure(
  'TRANSFER_PENDING',
  'A saved transfer needs attention before starting another.',
);

class SecureTransferStore implements TransferStore {
  SecureTransferStore(String namespace, {FlutterSecureStorage? storage})
    : _prefix = 'banking.f4.${base64Url.encode(utf8.encode(namespace))}',
      _storage = storage ?? const FlutterSecureStorage();
  final String _prefix;
  final FlutterSecureStorage _storage;
  static final Map<String, Future<void>> _tails = {};
  Future<T> _serial<T>(int user, Future<T> Function(String key) action) {
    final key = '$_prefix.$user.transfer';
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

  Future<SavedTransfer?> _read(String key) async {
    final value = await _storage.read(key: key);
    if (value == null) return null;
    try {
      return SavedTransfer.fromJson(jsonDecode(value));
    } catch (_) {
      throw invalidTransfer;
    }
  }

  @override
  Future<SavedTransfer?> read(int user) => _serial(user, _read);
  @override
  Future<void> claim(int user, SavedTransfer record) =>
      _serial(user, (key) async {
        if (await _read(key) != null) throw pendingTransfer;
        if (!record.unresolved) throw invalidTransfer;
        await _storage.write(key: key, value: jsonEncode(record.toJson()));
      });
  @override
  Future<void> resolve(int user, SavedTransfer record) => _serial(user, (
    key,
  ) async {
    final saved = await _read(key);
    if (saved == null ||
        saved.key != record.key ||
        record.unresolved ||
        jsonEncode(saved.draft.payload) != jsonEncode(record.draft.payload)) {
      throw invalidTransfer;
    }
    if (!saved.unresolved &&
        jsonEncode(saved.toJson()) != jsonEncode(record.toJson())) {
      throw invalidTransfer;
    }
    await _storage.write(key: key, value: jsonEncode(record.toJson()));
  });
  @override
  Future<void> dismiss(int user, String requestKey) =>
      _serial(user, (key) async {
        final saved = await _read(key);
        if (saved == null) return;
        if (saved.key != requestKey || saved.unresolved) throw pendingTransfer;
        await _storage.delete(key: key);
      });
}

class MemoryTransferStore implements TransferStore {
  final Map<int, SavedTransfer> _saved = {};
  @override
  Future<SavedTransfer?> read(int user) async => _saved[user];
  @override
  Future<void> claim(int user, SavedTransfer record) async {
    if (_saved[user] != null) throw pendingTransfer;
    if (!record.unresolved) throw invalidTransfer;
    _saved[user] = record;
  }

  @override
  Future<void> resolve(int user, SavedTransfer record) async {
    final saved = _saved[user];
    if (saved == null ||
        saved.key != record.key ||
        record.unresolved ||
        jsonEncode(saved.draft.payload) != jsonEncode(record.draft.payload)) {
      throw invalidTransfer;
    }
    _saved[user] = record;
  }

  @override
  Future<void> dismiss(int user, String key) async {
    final saved = _saved[user];
    if (saved == null) return;
    if (saved.key != key || saved.unresolved) throw pendingTransfer;
    _saved.remove(user);
  }
}
