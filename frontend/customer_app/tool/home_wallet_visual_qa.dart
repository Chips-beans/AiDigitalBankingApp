// Offline render fixture for Home overflow checks and the Wallet & Accounts page.
// No real accounts or services are used; output goes to .local/qa/home-wallet.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/app/banking_app.dart';
import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/accounts/account_gateway.dart';
import 'package:customer_app/features/accounts/creation_store.dart';
import 'package:customer_app/features/auth/data/auth_gateway.dart';
import 'package:customer_app/features/auth/presentation/continuation_pages.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:customer_app/shared/money.dart';
import 'package:customer_app/features/home/presentation/kesor_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/accounts_widget_test.dart' show FakePairAccounts;
import '../test/support/fakes.dart';

Future<void> _loadFonts(WidgetTester tester) => tester.runAsync(() async {
  for (final family in {
    'MaterialIcons': ['fonts/MaterialIcons-Regular.otf'],
    'Google Sans': [
      'assets/fonts/GoogleSans-Regular.ttf',
      'assets/fonts/GoogleSans-Medium.ttf',
      'assets/fonts/GoogleSans-Bold.ttf',
    ],
    'Poppins': [
      'assets/fonts/Poppins-Regular.ttf',
      'assets/fonts/Poppins-Medium.ttf',
      'assets/fonts/Poppins-SemiBold.ttf',
    ],
    'Noto Sans Khmer': ['assets/fonts/NotoSansKhmer-Variable.ttf'],
  }.entries) {
    final loader = FontLoader(family.key);
    for (final file in family.value) {
      loader.addFont(rootBundle.load(file));
    }
    await loader.load();
  }
});

Future<void> _capture(WidgetTester tester, Finder target, String name) =>
    tester.runAsync(() async {
      final image = await (tester.renderObject(target) as RenderRepaintBoundary)
          .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File('.local/qa/home-wallet/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    });

void main() {
  welcomeRenders();
  testWidgets('render Home across sizes, locales, themes and text scales', (
    tester,
  ) async {
    await _loadFonts(tester);
    final boundary = GlobalKey();
    final failures = <String>[];
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in const [
      Size(320, 640),
      Size(360, 780),
      Size(393, 852),
      Size(440, 999),
    ]) {
      for (final locale in const [Locale('km'), Locale('en')]) {
        for (final mode in Brightness.values) {
          for (final scale in const [1.0, 1.3, 2.0]) {
            final name =
                'home-${size.width.toInt()}-${locale.languageCode}-${mode.name}-$scale';
            final prefs = AppPreferences()..locale = locale;
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            await tester.pumpWidget(
              AppPreferencesScope(
                preferences: prefs,
                child: MaterialApp(
                  key: ValueKey(name),
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.build(mode, locale: locale),
                  home: MediaQuery(
                    data: MediaQueryData(
                      size: size,
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: RepaintBoundary(
                      key: boundary,
                      child: KesorHomeScreen(
                        data: _stress,
                        pendingTransfer: true,
                        errorMessage: _error,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final error = tester.takeException();
            if (error != null) failures.add('$name: $error');
            if (scale == 1.0 || error != null) {
              await _capture(tester, find.byKey(boundary), name);
            }
            await tester.pumpWidget(const SizedBox.shrink());
            prefs.dispose();
          }
        }
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  testWidgets('render Wallet & Accounts across sizes, locales and themes', (
    tester,
  ) async {
    await _loadFonts(tester);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final failures = <String>[];
    for (final size in const [Size(360, 1400), Size(440, 1400)]) {
      for (final locale in const [Locale('km'), Locale('en')]) {
        for (final mode in Brightness.values) {
          for (final scale in const [1.0, 2.0]) {
            final name =
                'wallet-${size.width.toInt()}-${locale.languageCode}-${mode.name}-$scale';
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            final auth = FakeGateway()..expiresInMs = 600000;
            final session = SessionController(auth, MemorySessionVault());
            await session.initialize();
            await session.begin(
              email: 'customer@example.test',
              password: 'Password1!',
              register: false,
            );
            await session.verifyCode('123456');
            final prefs = AppPreferences()
              ..locale = locale
              ..themeMode = mode == Brightness.dark
                  ? ThemeMode.dark
                  : ThemeMode.light;
            final gateway = FakePairAccounts()
              ..data = [
                _account(1, 'USD', '168.50'),
                _account(2, 'KHR', '1250000'),
                _account(3, 'USD', '98765432.10', status: 'FROZEN'),
                _account(4, 'KHR', '0', status: 'CLOSED'),
              ];
            await tester.pumpWidget(
              RepaintBoundary(
                key: ValueKey(name),
                child: BankingApp(
                  session: session,
                  preferences: prefs,
                  config: AppConfig(
                    apiBaseUrl: 'http://localhost:8080/api/v1',
                    environment: 'dev',
                  ),
                  accountGateway: gateway,
                  creationStore: MemoryCreationStore(),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip('View accounts'));
            await tester.pumpAndSettle();
            final error = tester.takeException();
            if (error != null) failures.add('$name: $error');
            await _capture(tester, find.byKey(ValueKey(name)), name);
            await tester.pumpWidget(const SizedBox.shrink());
            session.dispose();
            prefs.dispose();
          }
        }
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}

void welcomeRenders() {
  testWidgets('render welcome on a phone with system insets', (tester) async {
    await _loadFonts(tester);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final failures = <String>[];
    // TECNO LJ6 (1080x2460 @ 2.75) plus a short 360x740 phone.
    for (final size in const [Size(392.7, 894.5), Size(360, 740)]) {
      for (final mode in Brightness.values) {
        final name = 'welcome-${size.width.toInt()}-${mode.name}';
        final session = SessionController(
          DemoAuthGateway(),
          MemorySessionVault(),
        );
        await session.initialize();
        final prefs = AppPreferences()..locale = const Locale('en');
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          AppPreferencesScope(
            preferences: prefs,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.build(mode, locale: prefs.locale),
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  padding: const EdgeInsets.only(top: 32, bottom: 16),
                  viewPadding: const EdgeInsets.only(top: 32, bottom: 16),
                ),
                child: RepaintBoundary(
                  key: ValueKey(name),
                  child: ContinueWelcomePage(session),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => precacheImage(
            AssetImage(
              'assets/auth/${mode == Brightness.dark ? 'auth-night' : 'auth-day'}.png',
            ),
            tester.element(find.byKey(ValueKey(name))),
          ),
        );
        await tester.pumpAndSettle();
        final error = tester.takeException();
        if (error != null) failures.add('$name: $error');
        final scroll = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        if (scroll.position.maxScrollExtent > 0) {
          failures.add('$name scrolls by ${scroll.position.maxScrollExtent}');
        }
        await _capture(tester, find.byKey(ValueKey(name)), name);
        await tester.pumpWidget(const SizedBox.shrink());
        session.dispose();
        prefs.dispose();
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}

BankAccount _account(
  int id,
  String currency,
  String balance, {
  String status = 'ACTIVE',
}) => BankAccount(
  id: id,
  number: '${1000000000 + id}',
  type: 'SAVINGS',
  balance: Money.parse(balance, currency),
  status: status,
  createdAt: DateTime.utc(2026),
);

const _error =
    'Home could not refresh. Pull down to retry. Previously loaded values may be out of date.';
const _stress = KesorHomeData(
  khrBalance: '1,234,567,890,123',
  usdBalance: r'$98,765,432.10',
  recipients: [
    HomeRecipient('Sokha Chanthavy Vannarith', accountNumber: '1000000002'),
    HomeRecipient('1000000003', accountNumber: '1000000003'),
    HomeRecipient('ស៊ុន សុខា', accountNumber: '1000000004'),
  ],
  transactions: [
    HomeTransaction(
      name: 'Between your accounts · Pending',
      time: '11:59 PM',
      amount: '↔ 4,100,000.00 ៛',
      incoming: false,
      internal: true,
    ),
    HomeTransaction(
      name: 'Kesor Bank',
      time: '9:36 AM',
      amount: r'+$12,345,678.90',
      incoming: true,
      bank: true,
    ),
    HomeTransaction(
      name: 'A very long counterparty name for a transfer · Reversed',
      time: '7:34 AM',
      amount: r'-$2.80',
      incoming: false,
      dateLabel: '2026-10-20',
    ),
  ],
);
