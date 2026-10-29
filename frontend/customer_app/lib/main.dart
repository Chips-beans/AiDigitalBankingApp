import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/banking_app.dart';
import 'app/app_preferences.dart';
import 'app/preferences_store.dart';
import 'core/config/app_config.dart';
import 'core/network/api_client.dart';
import 'core/storage/session_vault.dart';
import 'features/auth/data/auth_gateway.dart';
import 'features/auth/data/app_pin_gateway.dart';
import 'features/auth/session_controller.dart';
import 'features/accounts/account_gateway.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = AppPreferences(store: createPreferencesStore());
  await preferences.load();
  final config = AppConfig.fromEnvironment();
  final client = ApiClient(config);
  final AuthGateway gateway = config.isDemo
      ? DemoAuthGateway()
      : HttpAuthGateway(client);
  final SessionVault vault = kIsWeb
      ? MemorySessionVault()
      : SecureSessionVault('${config.apiBaseUrl}|${config.mode}');
  final session = SessionController(
    gateway,
    vault,
    pinGateway: config.isDemo
        ? DemoAppPinGateway(gateway)
        : HttpAppPinGateway(client),
    deviceType: kIsWeb ? 'WEB' : defaultTargetPlatform.name.toUpperCase(),
  );
  runApp(
    BankingApp(
      preferences: preferences,
      session: session,
      config: config,
      accountGateway: config.isDemo
          ? DemoAccountGateway()
          : HttpAccountGateway(client),
    ),
  );
  unawaited(session.initialize());
}
