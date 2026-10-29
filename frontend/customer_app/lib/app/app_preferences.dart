import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'preferences_store_base.dart';

class AppPreferences extends ChangeNotifier {
  AppPreferences({PreferencesStore? store})
    : _store = store ?? MemoryPreferencesStore();
  final PreferencesStore _store;
  ThemeMode themeMode = ThemeMode.system;
  Locale locale = const Locale('en');
  Future<void> _pendingWrite = Future<void>.value();

  bool get isKhmer => locale.languageCode == 'km';

  Future<void> load() async {
    try {
      final raw = await _store.read();
      if (raw == null) return;
      final data = jsonDecode(raw);
      if (data is! Map) return;
      themeMode =
          ThemeMode.values
              .where((mode) => mode.name == data['theme'])
              .firstOrNull ??
          ThemeMode.system;
      locale = Locale(data['language'] == 'km' ? 'km' : 'en');
    } catch (_) {
      // Display preference storage must never block sign-in or banking.
    }
    notifyListeners();
  }

  void toggleTheme(Brightness current) {
    themeMode = current == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
    _changed();
  }

  void toggleLanguage() {
    locale = Locale(isKhmer ? 'en' : 'km');
    _changed();
  }

  void _changed() {
    notifyListeners();
    final value = jsonEncode({
      'theme': themeMode.name,
      'language': locale.languageCode,
    });
    // Serialize rapid toggles, so an older write cannot overwrite the latest.
    _pendingWrite = _pendingWrite
        .then((_) => _store.write(value))
        .catchError((Object _) {});
    unawaited(_pendingWrite);
  }

  Future<void> get saved => _pendingWrite;

  static AppPreferences? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppPreferencesScope>()
      ?.notifier;
  static AppPreferences of(BuildContext context) => maybeOf(context)!;
}

class AppPreferencesScope extends InheritedNotifier<AppPreferences> {
  const AppPreferencesScope({
    required AppPreferences preferences,
    required super.child,
    super.key,
  }) : super(notifier: preferences);
}

String tr(BuildContext context, String english, String khmer) =>
    AppPreferences.maybeOf(context)?.isKhmer == true ? khmer : english;
