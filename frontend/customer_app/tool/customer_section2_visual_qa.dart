import 'dart:io';
import 'dart:ui' as ui;

import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/features/accounts/accounts_controller.dart';
import 'package:customer_app/features/accounts/creation_store.dart';
import 'package:customer_app/features/analytics/analytics_controller.dart';
import 'package:customer_app/features/analytics/analytics_gateway.dart';
import 'package:customer_app/features/analytics/presentation/analytics_screen.dart';
import 'package:customer_app/features/transactions/presentation/kesor_transfer_screen.dart';
import 'package:customer_app/features/transactions/recipient_favorites.dart';
import 'package:customer_app/features/transactions/transfer_controller.dart';
import 'package:customer_app/features/transactions/transfer_models.dart';
import 'package:customer_app/features/transactions/transfer_store.dart';
import 'package:customer_app/shared/widgets/kesor_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/accounts_test.dart' show FakeAccounts;
import '../test/analytics_test.dart' show loadAnalyticsFonts;
import '../test/qr_pairs_test.dart' show signedSession;
import '../test/transactions_test.dart' show FakeTransactions, funded;

void main() {
  testWidgets('section 2: reference and compact layouts remain on one screen', (
    tester,
  ) async {
    await loadAnalyticsFonts(tester);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = await signedSession();
    final accounts = AccountsController(
      session,
      FakeAccounts()
        ..data = [
          funded(1, balance: '168'),
          funded(3, currency: 'KHR', balance: '100000'),
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
    final transfers = TransferController(
      session,
      FakeTransactions(),
      MemoryTransferStore(),
    );
    await transfers.initialize();
    addTearDown(() {
      analytics.dispose();
      transfers.dispose();
      accounts.dispose();
      session.dispose();
    });
    var count = 0;
    for (final screen in ['qr', 'analytics']) {
      for (final size in [
        const Size(440, 956),
        const Size(320, 568),
        const Size(375, 812),
        const Size(667, 375),
        const Size(844, 390),
        const Size(800, 1280),
      ]) {
        for (final dark in [false, true]) {
          for (final km in [false, true]) {
            for (final scale in [1.0, 1.3, 2.0]) {
              final reference = size.width == 440;
              final viewport = screen == 'qr' && reference
                  ? const Size(440, 957)
                  : size;
              tester.view.physicalSize = viewport;
              final preferences = AppPreferences()
                ..locale = Locale(km ? 'km' : 'en');
              final boundary = GlobalKey();
              final currency = scale == 1.3 ? 'KHR' : 'USD';
              await accounts.select(
                accounts.accounts.firstWhere((a) => a.currency == currency),
              );
              await analytics.selectCurrency(currency);
              await tester.pumpWidget(
                MaterialApp(
                  debugShowCheckedModeBanner: false,
                  locale: preferences.locale,
                  supportedLocales: const [Locale('en'), Locale('km')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: AppTheme.build(
                    dark ? Brightness.dark : Brightness.light,
                    locale: preferences.locale,
                  ),
                  home: MediaQuery(
                    data: MediaQueryData(
                      size: viewport,
                      textScaler: TextScaler.linear(scale),
                      padding: reference
                          ? EdgeInsets.zero
                          : const EdgeInsets.only(top: 24, bottom: 24),
                    ),
                    child: AppPreferencesScope(
                      preferences: preferences,
                      child: RepaintBoundary(
                        key: boundary,
                        child: screen == 'qr'
                            ? KesorTransferScreen(
                                key: UniqueKey(),
                                controller: transfers,
                                accounts: accounts,
                                enabled: true,
                                onBack: () {},
                                favorites: RecipientFavoritesStore(),
                                showDeviceChrome: reference,
                                prefill: TransferPrefill(
                                  funded(2).number,
                                  name: scale == 2
                                      ? 'Sok Sophea Long Recipient Name For Layout Verification'
                                      : 'Sok Sophea',
                                  qrString: 'verified-fixture',
                                  fixedAmount: scale == 1.3
                                      ? funded(2, balance: '5').balance
                                      : null,
                                ),
                              )
                            : Scaffold(
                                body: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: AnalyticsScreen(
                                        controller: analytics,
                                        showDeviceChrome: reference,
                                      ),
                                    ),
                                    Positioned(
                                      left: 20,
                                      right: 20,
                                      bottom: 32,
                                      child: MediaQuery.withClampedTextScaling(
                                        maxScaleFactor: 1.3,
                                        child: Center(
                                          heightFactor: 1,
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              maxWidth: 400,
                                            ),
                                            child: KesorBottomBar(
                                              selectedIndex: 1,
                                              onSelected: (_) {},
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.runAsync(
                () => precacheImage(
                  const AssetImage('assets/analytics/figma-money-overview.png'),
                  boundary.currentContext!,
                ),
              );
              await tester.pumpAndSettle();
              final label =
                  '$screen-${viewport.width.toInt()}x${viewport.height.toInt()}-${dark ? 'dark' : 'light'}-${km ? 'km' : 'en'}-$scale';
              expect(tester.takeException(), isNull, reason: label);
              expect(find.byType(Scrollable), findsNothing, reason: label);
              if (screen == 'qr') {
                for (final key in [
                  'qr-key-1',
                  'qr-key-backspace',
                  'qr-transfer-continue',
                  'qr-transfer-back',
                ]) {
                  final finder = find.byKey(ValueKey(key));
                  expect(
                    finder.hitTestable(),
                    findsOneWidget,
                    reason: '$label $key',
                  );
                  final rect = tester.getRect(finder);
                  expect(
                    rect.top,
                    greaterThanOrEqualTo(0),
                    reason: '$label $key',
                  );
                  expect(
                    rect.bottom,
                    lessThanOrEqualTo(viewport.height),
                    reason: '$label $key',
                  );
                  expect(
                    rect.height,
                    greaterThanOrEqualTo(
                      viewport.width > viewport.height &&
                              key.startsWith('qr-key-')
                          ? 16
                          : 48,
                    ),
                    reason: '$label $key',
                  );
                }
              } else {
                final chart = tester.getRect(
                  find.byKey(const ValueKey('analytics-chart-card')),
                );
                final nav = tester.getRect(find.byType(KesorBottomBar));
                expect(chart.bottom, lessThanOrEqualTo(nav.top), reason: label);
                final left = tester.getRect(
                  find.byKey(const ValueKey('analytics-income-card')),
                );
                final right = tester.getRect(
                  find.byKey(const ValueKey('analytics-expense-card')),
                );
                expect(left.top, right.top, reason: label);
                expect(left.right, lessThan(right.left), reason: label);
              }
              await tester.runAsync(() async {
                final picture =
                    await (boundary.currentContext!.findRenderObject()!
                            as RenderRepaintBoundary)
                        .toImage();
                final bytes = await picture.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                picture.dispose();
                final file = File('.local/qa/customer-section-2/$label.png');
                await file.parent.create(recursive: true);
                await file.writeAsBytes(bytes!.buffer.asUint8List());
              });
              if (screen == 'qr' && scale == 1.0) {
                await tester.tap(find.byKey(const ValueKey('qr-key-5')));
                await tester.pumpAndSettle();
                expect(
                  tester
                      .widget<FilledButton>(
                        find.byKey(const ValueKey('qr-transfer-continue')),
                      )
                      .onPressed,
                  isNotNull,
                );
                await tester.tap(
                  find.byKey(const ValueKey('qr-transfer-continue')),
                );
                await tester.pumpAndSettle();
                expect(
                  transfers.review?.qrString,
                  'verified-fixture',
                  reason: label,
                );
                transfers.edit();
                await tester.pumpAndSettle();
                expect(
                  find.byKey(const ValueKey('qr-transfer-panel')),
                  findsOneWidget,
                );
              }
              count++;
              await tester.pumpWidget(const SizedBox.shrink());
              preferences.dispose();
            }
          }
        }
      }
    }
    // ignore: avoid_print
    print('Section 2: $count renders; no overflow or page scrolling.');
  });
}
