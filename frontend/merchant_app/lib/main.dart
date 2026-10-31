import 'package:flutter/material.dart';

import 'app/merchant_app.dart';
import 'core/merchant_config.dart';
import 'core/merchant_preferences.dart';
import 'features/auth/merchant_session.dart';
import 'features/auth/merchant_api_auth.dart';

import 'dart:async';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final config = MerchantConfig.fromEnvironment();
    final preferences = MerchantPreferences(
      store: SecureMerchantPreferenceStore(config),
    );
    await preferences.load();
    final session = MerchantSession(MerchantApiAuth(config));
    runApp(MerchantApp(preferences: preferences, session: session));
    unawaited(session.initialize());
  } on ArgumentError {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Kesor Merchant cannot connect with this configuration. Please contact support.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
