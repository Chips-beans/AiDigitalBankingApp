import 'package:web/web.dart' as web;

import 'preferences_store_base.dart';

PreferencesStore createPreferencesStore() => _BrowserPreferencesStore();

class _BrowserPreferencesStore implements PreferencesStore {
  // Display preferences only. Authentication tokens never enter localStorage.
  static const _key = 'kesor.ui.preferences.v1';
  @override
  Future<String?> read() async => web.window.localStorage.getItem(_key);
  @override
  Future<void> write(String value) async =>
      web.window.localStorage.setItem(_key, value);
}
