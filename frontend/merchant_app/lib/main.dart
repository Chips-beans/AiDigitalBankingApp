import 'package:flutter/material.dart';

import 'app/merchant_app.dart';
import 'core/merchant_config.dart';
import 'core/merchant_preferences.dart';
import 'features/auth/merchant_session.dart';
import 'features/auth/merchant_api_auth.dart';
import 'features/shop/merchant_shop_api.dart';

import 'package:kesor_auth_handoff/kesor_auth_handoff.dart'
    show SecureHandoffStore;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final config = MerchantConfig.fromEnvironment();
    final preferences = MerchantPreferences(
      store: SecureMerchantPreferenceStore(config),
    );
    await preferences.load();
    final auth = MerchantApiAuth(config);
    final session = MerchantSession(auth);
    runApp(
      MerchantApp(
        preferences: preferences,
        session: session,
        startup: session.initialize(),
        shopGateway: MerchantShopApi(config, auth),
        // Saved registration intents live in their own secure namespace.
        shopStore: SecureHandoffStore(
          '${config.storageNamespace}|${config.environment}|shop',
        ),
      ),
    );
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
