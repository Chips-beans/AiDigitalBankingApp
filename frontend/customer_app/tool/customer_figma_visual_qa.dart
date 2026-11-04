// Offline responsive evidence for all five frames in Figma section 387:6034.
// flutter test tool/customer_figma_visual_qa.dart --concurrency=1
import 'dart:io';
import 'dart:ui' as ui;

import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/features/accounts/accounts_controller.dart';
import 'package:customer_app/features/accounts/creation_store.dart';
import 'package:customer_app/features/accounts/presentation/wallet_accounts_screen.dart';
import 'package:customer_app/features/analytics/analytics_controller.dart';
import 'package:customer_app/features/analytics/analytics_gateway.dart';
import 'package:customer_app/features/analytics/presentation/analytics_screen.dart';
import 'package:customer_app/features/assistant/assistant_controller.dart';
import 'package:customer_app/features/assistant/assistant_store.dart';
import 'package:customer_app/features/assistant/presentation/assistant_screen.dart';
import 'package:customer_app/features/home/presentation/kesor_home_screen.dart';
import 'package:customer_app/features/qr/presentation/receive_qr_panel.dart';
import 'package:customer_app/shared/widgets/kesor_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/accounts_test.dart' show FakeAccounts;
import '../test/qr_pairs_test.dart' show signedSession, FakeQr;
import '../test/transactions_test.dart' show funded;
import '../test/support/assistant_fakes.dart' show FakeAssistant;

void main() {
  testWidgets('five Customer Figma screens adapt without overflow', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final entry in {
        'MaterialIcons': ['fonts/MaterialIcons-Regular.otf'],
        'Poppins': [
          'assets/fonts/Poppins-Light.ttf',
          'assets/fonts/Poppins-Regular.ttf',
          'assets/fonts/Poppins-Medium.ttf',
          'assets/fonts/Poppins-SemiBold.ttf',
          'assets/fonts/Poppins-Bold.ttf',
        ],
        'Google Sans': [
          'assets/fonts/GoogleSans-Regular.ttf',
          'assets/fonts/GoogleSans-Medium.ttf',
          'assets/fonts/GoogleSans-Bold.ttf',
        ],
        'Noto Sans Khmer': ['assets/fonts/NotoSansKhmer-Variable.ttf'],
      }.entries) {
        final loader = FontLoader(entry.key);
        for (final file in entry.value) {
          loader.addFont(rootBundle.load(file));
        }
        await loader.load();
      }
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final failures = <String>[];
    var renders = 0;
    for (final size in const [
      Size(440, 999),
      Size(375, 812),
      Size(320, 568),
      Size(812, 375),
      Size(1024, 768),
    ]) {
      tester.view.physicalSize = size;
      for (final locale in ['en', 'km']) {
        for (final brightness in Brightness.values) {
          for (final scale in [1.0, 1.3, 2.0]) {
            final session = await signedSession();
            final accounts = AccountsController(
              session,
              FakeAccounts()
                ..data = [
                  funded(1, balance: '168.00'),
                  funded(2, currency: 'KHR', balance: '2000'),
                ],
              MemoryCreationStore(),
            );
            await accounts.initialize();
            final analytics = AnalyticsController(
              session,
              DemoAnalyticsGateway(),
              clock: () => DateTime.utc(2025, 10),
            );
            await analytics.refresh();
            final assistant = AssistantController(
              session,
              FakeAssistant(),
              AssistantPendingStore(),
            );
            await assistant.initialize();
            final prefs = AppPreferences()..locale = Locale(locale);
            void noop() {}
            final screens = <String, Widget>{
              'home': const KesorHomeScreen(
                data: KesorHomeData.designPreview,
                showDeviceChrome: true,
              ),
              'wallet': WalletAccountsScreen(
                model: accounts,
                greetingName: 'Sovanreach',
                onBack: noop,
                onProfile: noop,
                onRefresh: () async {},
                onTransfer: noop,
                onMyQr: noop,
                onOpenAccounts: noop,
                onDetails: noop,
                onActivity: noop,
                bottomBar: const SizedBox.shrink(),
              ),
              'analytics': Scaffold(
                body: Stack(
                  children: [
                    Positioned.fill(
                      child: AnalyticsScreen(
                        controller: analytics,
                        showDeviceChrome: false,
                      ),
                    ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 24,
                      child: KesorBottomBar(
                        selectedIndex: 1,
                        onSelected: (_) {},
                      ),
                    ),
                  ],
                ),
              ),
              'assistant': Scaffold(
                body: AssistantScreen(
                  controller: assistant,
                  onAction: (_) {},
                  bottomClearance: 0,
                  onBack: noop,
                ),
              ),
              'qr': ReceiveQrScreen(
                background: const KesorHomeScreen(
                  data: KesorHomeData.designPreview,
                  showDeviceChrome: true,
                ),
                panel: ReceiveQrPanel(
                  session: session,
                  gateway: FakeQr(),
                  accounts: accounts,
                  onClose: noop,
                ),
              ),
            };
            for (final entry in screens.entries) {
              final surfaceSize = entry.key == 'assistant' && size.width == 440
                  ? const Size(440, 860)
                  : size;
              tester.view.physicalSize = surfaceSize;
              final key = GlobalKey();
              final name =
                  '${entry.key}-${size.width.toInt()}-$locale-${brightness.name}-$scale';
              await tester.pumpWidget(
                AppPreferencesScope(
                  preferences: prefs,
                  child: MaterialApp(
                    key: ValueKey(name),
                    debugShowCheckedModeBanner: false,
                    theme: AppTheme.build(brightness, locale: prefs.locale),
                    locale: prefs.locale,
                    supportedLocales: const [Locale('en'), Locale('km')],
                    localizationsDelegates:
                        GlobalMaterialLocalizations.delegates,
                    home: MediaQuery(
                      data: MediaQueryData(
                        size: surfaceSize,
                        textScaler: TextScaler.linear(scale),
                        padding: EdgeInsets.only(
                          top: entry.key == 'wallet' ? 44 : 54,
                          bottom: 24,
                        ),
                        disableAnimations: true,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: RepaintBoundary(key: key, child: entry.value),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              Object? error;
              while ((error = tester.takeException()) != null) {
                failures.add('$name: $error');
              }
              if (size.width == 440 && scale == 1 ||
                  failures.any((f) => f.startsWith(name))) {
                await tester.runAsync(() async {
                  final bitmap =
                      await (key.currentContext!.findRenderObject()
                              as RenderRepaintBoundary)
                          .toImage();
                  final bytes = await bitmap.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  final file = File('.local/qa/figma-redesign/$name.png');
                  await file.parent.create(recursive: true);
                  await file.writeAsBytes(bytes!.buffer.asUint8List());
                  bitmap.dispose();
                });
              }
              for (final element in find.byType(Scrollable).evaluate()) {
                final state =
                    (element as StatefulElement).state as ScrollableState;
                if (state.position.axis == Axis.vertical) {
                  state.position.jumpTo(state.position.maxScrollExtent);
                }
              }
              await tester.pump();
              while ((error = tester.takeException()) != null) {
                failures.add('$name scrolled: $error');
              }
              renders++;
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump();
            }
            assistant.dispose();
            analytics.dispose();
            accounts.dispose();
            session.dispose();
            prefs.dispose();
          }
        }
      }
    }
    await tester.runAsync(
      () => File('.local/qa/figma-redesign/responsive-result.txt').writeAsString(
        '$renders renders\n${failures.isEmpty ? 'No layout exceptions' : failures.join('\n')}',
      ),
    );
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
