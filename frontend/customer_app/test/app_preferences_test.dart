import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/banking_app.dart';
import 'package:customer_app/app/preferences_store_base.dart';
import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/auth/data/auth_gateway.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'theme and language persist; corrupt display preferences use safe defaults',
    () async {
      final store = MemoryPreferencesStore();
      final first = AppPreferences(store: store);
      first.toggleTheme(Brightness.light);
      first.toggleLanguage();
      first.toggleTheme(Brightness.dark);
      first.toggleTheme(Brightness.light);
      await first.saved;
      final restored = AppPreferences(store: store);
      await restored.load();
      expect(restored.themeMode, ThemeMode.dark);
      expect(restored.locale, const Locale('km'));
      store.value = 'invalid json';
      final invalid = AppPreferences(store: store);
      await invalid.load();
      expect(invalid.themeMode, ThemeMode.system);
      expect(invalid.locale, const Locale('en'));
      first.dispose();
      restored.dispose();
      invalid.dispose();
    },
  );

  testWidgets(
    'login controls switch the entire app and remain selected after onboarding',
    (tester) async {
      final prefs = AppPreferences();
      final session = SessionController(
        DemoAuthGateway(),
        MemorySessionVault(),
      );
      await session.initialize();
      await tester.pumpWidget(
        BankingApp(
          session: session,
          preferences: prefs,
          config: AppConfig(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            environment: 'dev',
            mode: 'demo',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('theme-toggle')));
      await tester.tap(find.byKey(const ValueKey('theme-toggle')));
      await tester.pumpAndSettle();
      expect(prefs.themeMode, ThemeMode.dark);
      await tester.tap(find.byKey(const ValueKey('language-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('បន្តជាមួយអ៊ីមែល'), findsOneWidget);
      await tester.ensureVisible(find.text('បន្តជាមួយអ៊ីមែល'));
      await tester.tap(find.text('បន្តជាមួយអ៊ីមែល'));
      await tester.pumpAndSettle();
      expect(find.text('អាសយដ្ឋានអ៊ីមែល'), findsOneWidget);
      await session.beginEmail('dara@example.test');
      await session.verifyCode('123456');
      await session.completeInformation('Dara', 'Sok');
      await tester.pumpAndSettle();
      expect(find.text('សមតុល្យ'), findsOneWidget);
      expect(prefs.locale, const Locale('km'));
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      await tester.tap(find.byKey(const ValueKey('bottom-tab-1')));
      await tester.pumpAndSettle();
      expect(find.text('ការវិភាគ'), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('analytics-income-card')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      prefs.dispose();
      session.dispose();
    },
  );
}
