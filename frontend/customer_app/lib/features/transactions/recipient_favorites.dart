import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/network/api_client.dart';

class FavoriteRecipient {
  const FavoriteRecipient(this.number, this.currency);
  factory FavoriteRecipient.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['number'] is! String ||
        !RegExp(r'^[0-9]{10,20}$').hasMatch(value['number'] as String) ||
        !{'USD', 'KHR'}.contains(value['currency'])) {
      throw unavailable;
    }
    return FavoriteRecipient(
      value['number'] as String,
      value['currency'] as String,
    );
  }
  final String number, currency;
  Map<String, String> toJson() => {'number': number, 'currency': currency};
  bool same(FavoriteRecipient other) =>
      number == other.number && currency == other.currency;
  static const unavailable = ApiFailure(
    'FAVORITES_UNAVAILABLE',
    'Saved recipients could not be loaded. You can still enter an account number.',
  );
}

/// Device-local bookmarks, never a financial authorization or recipient lookup.
/// Native values are encrypted by FlutterSecureStorage; previews use memory.
class RecipientFavoritesStore {
  RecipientFavoritesStore({String? namespace, FlutterSecureStorage? storage})
    : _prefix = namespace == null
          ? null
          : 'banking.recipient-favorites.${base64Url.encode(utf8.encode(namespace))}',
      _storage = storage ?? const FlutterSecureStorage();
  final String? _prefix;
  final FlutterSecureStorage _storage;
  final _memory = <int, List<FavoriteRecipient>>{};
  static final _tails = <String, Future<void>>{};
  Future<T> _serial<T>(int user, Future<T> Function(String?) work) {
    final key = _prefix == null ? null : '$_prefix.$user';
    final lock = key ?? 'memory-favorites-${identityHashCode(this)}.$user';
    final result = (_tails[lock] ?? Future<void>.value()).then(
      (_) => work(key),
    );
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

  Future<List<FavoriteRecipient>> _read(int user, String? key) async {
    if (key == null) return List.of(_memory[user] ?? []);
    final raw = await _storage.read(key: key);
    if (raw == null) return [];
    try {
      final data = jsonDecode(raw);
      if (data is! Map ||
          data['version'] != 1 ||
          data['recipients'] is! List ||
          (data['recipients'] as List).length > 50) {
        throw FavoriteRecipient.unavailable;
      }
      return (data['recipients'] as List)
          .map(FavoriteRecipient.fromJson)
          .toList();
    } catch (_) {
      throw FavoriteRecipient.unavailable;
    }
  }

  Future<List<FavoriteRecipient>> read(int user) =>
      _serial(user, (key) => _read(user, key));
  Future<void> _write(
    int user,
    String? key,
    List<FavoriteRecipient> list,
  ) async {
    if (key == null) {
      _memory[user] = list;
    } else {
      await _storage.write(
        key: key,
        value: jsonEncode({
          'version': 1,
          'recipients': list.map((r) => r.toJson()).toList(),
        }),
      );
    }
  }

  Future<void> add(int user, FavoriteRecipient recipient) =>
      _serial(user, (key) async {
        FavoriteRecipient.fromJson(recipient.toJson());
        final current = await _read(user, key);
        await _write(
          user,
          key,
          [
            recipient,
            ...current.where((r) => !r.same(recipient)),
          ].take(50).toList(),
        );
      });
  Future<void> remove(int user, FavoriteRecipient recipient) => _serial(user, (
    key,
  ) async {
    final current = await _read(user, key);
    await _write(user, key, current.where((r) => !r.same(recipient)).toList());
  });
}
