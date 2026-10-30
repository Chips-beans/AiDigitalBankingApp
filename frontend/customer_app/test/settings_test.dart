import 'dart:async';

import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/app/preferences_store_base.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/auth/data/auth_gateway.dart';
import 'package:customer_app/features/auth/data/app_pin_gateway.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:customer_app/features/settings/settings_screen.dart';
import 'package:customer_app/features/settings/settings_detail_screen.dart';
import 'package:customer_app/features/settings/settings_platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSettingsPlatform extends SettingsPlatform {
  int alerts = 0, opens = 0, emails = 0;
  @override
  bool get supportsNotifications => true;
  @override
  Future<bool> notificationsEnabled() async => true;
  @override
  Future<bool> activityAlert() async {
    alerts++;
    return true;
  }

  @override
  Future<void> openNotifications() async {
    opens++;
  }

  @override
  Future<bool> emailSupport() async {
    emails++;
    return true;
  }
}

class DelayedProfileAuth extends DemoAuthGateway {
  Completer<void>? gate;
  @override
  Future<SessionIdentity> completeProfile(
    String access,
    String firstName,
    String lastName,
  ) async {
    final result = await super.completeProfile(access, firstName, lastName);
    await gate?.future;
    return result;
  }
}

Future<SessionController> settingsSession({bool withPin = false}) async {
  final auth = DemoAuthGateway();
  final session = SessionController(
    auth,
    MemorySessionVault(),
    pinGateway: withPin ? DemoAppPinGateway(auth) : null,
  );
  await session.initialize();
  session.openEmail();
  await session.beginEmail('settings@example.test');
  await session.verifyCode('123456');
  await session.completeInformation('Seng', 'Sovanreach');
  if (withPin) {
    await session.submitPin('0427');
    await session.submitPin('0427');
  }
  return session;
}

Widget settingsHost(AppPreferences prefs, Widget child) => AppPreferencesScope(
  preferences: prefs,
  child: ListenableBuilder(
    listenable: prefs,
    builder: (_, _) => MaterialApp(
      theme: AppTheme.build(
        prefs.themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light,
        locale: prefs.locale,
      ),
      home: child,
    ),
  ),
);

void main() {
  test(
    'late profile save cannot restore private identity after sign-out',
    () async {
      final auth = DelayedProfileAuth();
      final session = SessionController(auth, MemorySessionVault());
      await session.initialize();
      session.openEmail();
      await session.beginEmail('late-settings@example.test');
      await session.verifyCode('123456');
      await session.completeInformation('Sok', 'Dara');
      auth.gate = Completer<void>();
      final pending = session.updateProfileDetails('Private', 'Name');
      await Future<void>.delayed(Duration.zero);
      await session.signOut();
      auth.gate!.complete();
      expect(await pending, isFalse);
      expect(session.identity, isNull);
      expect(session.phase, SessionPhase.signedOut);
      session.dispose();
    },
  );
  test(
    'settings selections persist, including returning to system theme',
    () async {
      final store = MemoryPreferencesStore();
      final prefs = AppPreferences(store: store)
        ..setLanguage(const Locale('km'))
        ..setThemeMode(ThemeMode.dark)
        ..setActivityAlerts(true)
        ..setThemeMode(ThemeMode.system);
      await prefs.saved;
      final restored = AppPreferences(store: store);
      await restored.load();
      expect(restored.locale.languageCode, 'km');
      expect(restored.themeMode, ThemeMode.system);
      expect(restored.activityAlerts, isTrue);
      prefs.dispose();
      restored.dispose();
    },
  );
  test(
    'PIN change requires current PIN, replaces PIN and keeps five-attempt lock',
    () async {
      final session = await settingsSession(withPin: true);
      expect(await session.changePin('1111', '6874', '6874'), isFalse);
      expect(session.failure?.code, 'PIN_INVALID');
      expect(await session.changePin('0427', '6874', '6874'), isTrue);
      expect(session.phase, SessionPhase.signedIn);
      session.lockApp();
      await Future<void>.delayed(Duration.zero);
      expect(await session.submitPin('0427'), isFalse);
      expect(await session.submitPin('6874'), isTrue);
      for (var i = 0; i < 5; i++) {
        expect(await session.changePin('1111', '5072', '5072'), isFalse);
      }
      expect(session.phase, SessionPhase.pinLocked);
      await Future<void>.delayed(Duration.zero);
      expect(session.pinChallenge?.recoveryRequired, isTrue);
      session.dispose();
    },
  );
  testWidgets(
    'root uses live name, Figma geometry, working rows and disabled biometrics',
    (tester) async {
      await tester.runAsync(() async {
        final font = FontLoader('Poppins')
          ..addFont(rootBundle.load('assets/fonts/Poppins-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Poppins-SemiBold.ttf'));
        await font.load();
      });
      tester.view.physicalSize = const Size(440, 999);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = await settingsSession();
      final prefs = AppPreferences();
      String? opened;
      await tester.pumpWidget(
        settingsHost(
          prefs,
          Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                size: Size(440, 999),
                padding: EdgeInsets.only(top: 54),
              ),
              child: SettingsScreen(
                session: session,
                onOpen: (value) => opened = value,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Seng Sovanreach'), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('settings-profile'))).top,
        148,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('settings-profile'))),
        const Size(400, 84),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('settings-pin'))).height,
        64,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('settings-notifications')))
            .height,
        60,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('settings-help'))).height,
        56,
      );
      await tester.tap(find.byKey(const ValueKey('settings-biometric')));
      expect(opened, isNull);
      for (final id in [
        'profile',
        'pin',
        'notifications',
        'language',
        'appearance',
        'help',
        'legal',
        'signout',
      ]) {
        final target = find.byKey(ValueKey('settings-$id'));
        await tester.ensureVisible(target);
        await tester.tap(target);
        expect(opened, id);
      }
      await session.updateProfileDetails('Sok', 'Dara');
      await tester.pumpAndSettle();
      expect(find.text('Sok Dara'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      prefs.dispose();
    },
  );
  testWidgets(
    'profile form saves real identity without relocking and PIN form validates',
    (tester) async {
      final session = await settingsSession(withPin: true);
      final prefs = AppPreferences();
      Widget page(String id) => settingsHost(
        prefs,
        SettingsDetailScreen(
          key: ValueKey(id),
          page: id,
          session: session,
          onBack: () {},
          onAssistant: () {},
        ),
      );
      await tester.pumpWidget(page('profile'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('settings-first-name')),
        'Sok',
      );
      await tester.enterText(
        find.byKey(const ValueKey('settings-last-name')),
        'Dara',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('settings-save')));
      await tester.tap(find.byKey(const ValueKey('settings-save')));
      await tester.pumpAndSettle();
      expect(session.identity?.displayName, 'Sok Dara');
      expect(session.phase, SessionPhase.signedIn);
      await tester.pumpWidget(page('pin'));
      await tester.pumpAndSettle();
      for (final entry in {
        'current-pin': '0427',
        'new-pin': '6874',
        'confirm-pin': '6875',
      }.entries) {
        await tester.enterText(find.byKey(ValueKey(entry.key)), entry.value);
      }
      await tester.ensureVisible(find.byKey(const ValueKey('settings-save')));
      await tester.tap(find.byKey(const ValueKey('settings-save')));
      await tester.pumpAndSettle();
      expect(find.text('PINs do not match.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('confirm-pin')), '6874');
      await tester.ensureVisible(find.byKey(const ValueKey('settings-save')));
      await tester.tap(find.byKey(const ValueKey('settings-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('PIN changed. Other sessions have been signed out.'),
        findsOneWidget,
      );
      expect(
        (tester.widget<TextFormField>(
          find.byKey(const ValueKey('current-pin')),
        )).controller!.text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      prefs.dispose();
    },
  );
  testWidgets(
    'device alerts, help email, assistant navigation, demo policies and signout work',
    (tester) async {
      final session = await settingsSession();
      final prefs = AppPreferences();
      final platform = FakeSettingsPlatform();
      bool assistant = false;
      Widget page(String id) => settingsHost(
        prefs,
        SettingsDetailScreen(
          key: ValueKey(id),
          page: id,
          session: session,
          platform: platform,
          onBack: () {},
          onAssistant: () => assistant = true,
        ),
      );
      await tester.pumpWidget(page('notifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(prefs.activityAlerts, isTrue);
      await tester.ensureVisible(find.text('Send test alert'));
      await tester.tap(find.text('Send test alert'));
      await tester.pumpAndSettle();
      expect(platform.alerts, 1);
      await tester.tap(find.text('Open Android notification settings'));
      expect(platform.opens, 1);
      await tester.pumpWidget(page('help'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Email support'));
      await tester.pumpAndSettle();
      expect(platform.emails, 1);
      await tester.tap(find.text('Ask the AI Assistant'));
      expect(assistant, isTrue);
      await tester.pumpWidget(page('legal'));
      await tester.pumpAndSettle();
      expect(find.text('Demo terms & privacy'), findsOneWidget);
      await tester.pumpWidget(page('signout'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-signout')));
      await tester.pumpAndSettle();
      expect(session.phase, SessionPhase.signedOut);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      prefs.dispose();
    },
  );
}
