import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'merchant_config.dart';

abstract interface class MerchantPreferenceStore {
  Future<String?> read();
  Future<void> write(String value);
}

class MemoryMerchantPreferenceStore implements MerchantPreferenceStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

/// Only display preferences here. Merchant authentication gets a separate store
/// and protocol in M2/M3; Customer storage is never opened by this app.
class SecureMerchantPreferenceStore implements MerchantPreferenceStore {
  SecureMerchantPreferenceStore(
    MerchantConfig config, {
    this.storage = const FlutterSecureStorage(),
  }) : _key = '${config.storageNamespace}|display';
  final FlutterSecureStorage storage;
  final String _key;
  @override
  Future<String?> read() => storage.read(key: _key);
  @override
  Future<void> write(String value) => storage.write(key: _key, value: value);
}

class MerchantPreferences extends ChangeNotifier {
  MerchantPreferences({MerchantPreferenceStore? store})
    : _store = store ?? MemoryMerchantPreferenceStore();
  final MerchantPreferenceStore _store;
  Locale locale = const Locale('en');
  ThemeMode themeMode = ThemeMode.system;
  bool get isKhmer => locale.languageCode == 'km';
  Future<void> _writes = Future.value();

  Future<void> load() async {
    try {
      final raw = await _store.read();
      if (raw != null) {
        final value = jsonDecode(raw);
        if (value is Map) {
          locale = Locale(value['locale'] == 'km' ? 'km' : 'en');
          themeMode =
              ThemeMode.values
                  .where((v) => v.name == value['theme'])
                  .firstOrNull ??
              ThemeMode.system;
        }
      }
    } catch (_) {
      /* Display preference failures must not prevent sign-in. */
    }
    notifyListeners();
  }

  void setLanguage(String code) {
    if (!{'en', 'km'}.contains(code)) return;
    locale = Locale(code);
    _changed();
  }

  void setTheme(ThemeMode mode) {
    themeMode = mode;
    _changed();
  }

  void _changed() {
    final value = jsonEncode({
      'locale': locale.languageCode,
      'theme': themeMode.name,
    });
    _writes = _writes
        .then((_) => _store.write(value))
        .catchError((Object _) {});
    unawaited(_writes);
    notifyListeners();
  }

  Future<void> get saved => _writes;
}
