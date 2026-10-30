import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'assistant_models.dart';

/// Only an immutable in-flight request is stored locally; conversation history stays on the server.
class AssistantPendingStore {
  AssistantPendingStore({String? namespace, FlutterSecureStorage? storage})
    : _prefix = namespace == null
          ? null
          : 'banking.ai.pending.${base64Url.encode(utf8.encode(namespace))}',
      _storage = storage ?? const FlutterSecureStorage();
  final String? _prefix;
  final FlutterSecureStorage _storage;
  final _memory = <int, AiPending>{};
  static final _tails = <String, Future<void>>{};
  Future<T> _serial<T>(int user, Future<T> Function(String?) action) {
    final key = _prefix == null ? null : '$_prefix.$user',
        lock = _prefix == null
            ? 'ai-memory-${identityHashCode(this)}.$user'
            : '$_prefix.$user';
    final result = (_tails[lock] ?? Future.value()).then((_) => action(key));
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tails[lock] = tail;
    tail.then((_) {
      if (identical(_tails[lock], tail)) _tails.remove(lock);
    });
    return result;
  }

  Future<AiPending?> _read(int user, String? key) async {
    try {
      if (key == null) return _memory[user];
      final raw = await _storage.read(key: key);
      if (raw != null && raw.length > 16000) throw assistantStorageFailure;
      return raw == null ? null : AiPending.fromJson(jsonDecode(raw));
    } catch (_) {
      throw assistantStorageFailure;
    }
  }

  Future<AiPending?> read(int user) => _serial(user, (key) => _read(user, key));
  Future<void> _write(int user, String? key, AiPending? value) async {
    try {
      if (key == null) {
        if (value == null) {
          _memory.remove(user);
        } else {
          _memory[user] = value;
        }
      } else if (value == null) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: jsonEncode(value.toJson()));
      }
    } catch (_) {
      throw assistantStorageFailure;
    }
  }

  Future<void> claim(int user, AiPending pending) => _serial(user, (key) async {
    if (await _read(user, key) != null) throw assistantStorageFailure;
    AiPending.fromJson(pending.toJson());
    await _write(user, key, pending);
  });
  Future<void> replace(int user, String previousKey, AiPending? value) =>
      _serial(user, (key) async {
        final old = await _read(user, key);
        if (old == null || old.key != previousKey) {
          throw assistantStorageFailure;
        }
        if (value != null) {
          AiPending.fromJson(value.toJson());
          final sameQuestion =
              old.message == value.message && old.locale == value.locale;
          final creation =
              sameQuestion &&
              old.phase == 'CREATE' &&
              value.phase == 'MESSAGE' &&
              !value.failed &&
              old.createdAt == value.createdAt;
          final failure =
              sameQuestion &&
              old.phase == value.phase &&
              old.key == value.key &&
              old.conversation == value.conversation &&
              old.createdAt == value.createdAt &&
              value.failed;
          final retry =
              sameQuestion &&
              old.failed &&
              old.phase == value.phase &&
              old.conversation == value.conversation &&
              !value.failed &&
              old.key != value.key;
          if (!creation && !failure && !retry) throw assistantStorageFailure;
        }
        await _write(user, key, value);
      });
}
