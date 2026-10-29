import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'preferences_store_base.dart';

PreferencesStore createPreferencesStore() => _NativePreferencesStore();

class _NativePreferencesStore implements PreferencesStore {
  static const _key = 'kesor.ui.preferences.v1';
  final _storage = const FlutterSecureStorage();
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
}
