import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_app/app/merchant_app.dart';
import 'package:merchant_app/core/merchant_preferences.dart';
import 'package:merchant_app/features/auth/merchant_session.dart';

import 'dart:convert';

import 'package:kesor_auth_handoff/kesor_auth_handoff.dart';
import 'package:merchant_app/features/shop/merchant_shop.dart';
import 'package:merchant_app/features/collect/merchant_collect.dart';
import 'package:merchant_app/features/collect/wallet_page.dart' show ReceiptRow;
import 'package:merchant_app/features/feed/payment_feed_controller.dart';

import '../test/merchant_foundation_test.dart' show ControlledMerchantAuth;
import '../test/merchant_shop_test.dart' show FakeShopGateway, readyProfile;
import '../test/merchant_transfer_test.dart' show fundedProfile;

import 'package:merchant_app/features/transfer/owner_transfer.dart'
    show TransferStatus;

void main() {
  testWidgets(
    'Merchant screens adapt across language, theme, size and accessibility',
    (tester) async {
      await tester.runAsync(() async {
        for (final entry in {
          'MaterialIcons': ['fonts/MaterialIcons-Regular.otf'],
          'Poppins': [
            'assets/fonts/Poppins-Regular.ttf',
            'assets/fonts/Poppins-Medium.ttf',
            'assets/fonts/Poppins-SemiBold.ttf',
            'assets/fonts/Poppins-Light.ttf',
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
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      for (final variant in [
        (name: 'phone', size: const Size(393, 852), scale: 1.0, km: false),
        (name: 'small', size: const Size(320, 640), scale: 1.0, km: false),
        (name: 'large-km', size: const Size(375, 812), scale: 2.0, km: true),
        (name: 'landscape', size: const Size(812, 375), scale: 1.0, km: false),
        (name: 'tablet-km', size: const Size(800, 1280), scale: 1.3, km: true),
        (
          name: 'tablet-landscape',
          size: const Size(1280, 800),
          scale: 1.0,
          km: false,
        ),
      ]) {
        tester.view.physicalSize = variant.size;
        tester.platformDispatcher.textScaleFactorTestValue = variant.scale;
        for (final brightness in Brightness.values) {
          for (final screen in [
            'welcome',
            'registration',
            'home',
            'collect',
            'sales',
            'sales-empty',
            'receipt',
            'reports-day',
            'reports-month',
            'requests',
            'more',
            'recovery',
            'shop-profile',
            'request-waiting',
            'request-paid',
            'wallet',
            if (variant.name == 'phone') ...[
              'collect-shop-qr',
              'request-cancelled',
              'waiting',
              'restricted',
              'pending-review',
              'registration-saved',
              'unavailable',
              'alert-banner',
              'owner-transfer-form',
              'owner-transfer-waiting',
              'owner-transfer-completed',
              'owner-transfer-failed',
            ],
          ]) {
            final prefs = MerchantPreferences()
              ..setLanguage(variant.km ? 'km' : 'en')
              ..setTheme(
                brightness == Brightness.dark
                    ? ThemeMode.dark
                    : ThemeMode.light,
              );
            final auth = ControlledMerchantAuth();
            final session = MerchantSession(
              screen == 'unavailable' ? UnavailableMerchantAuth() : auth,
            );
            if (screen != 'welcome') {
              final pending = session.signIn();
              if (screen == 'waiting') {
                unawaited(pending);
              } else if (screen == 'unavailable') {
                await pending;
              } else {
                auth.approval.complete(
                  MerchantIdentity(
                    ownerId: 1,
                    recoveryRequired: screen == 'recovery',
                    shop:
                        screen.startsWith('registration') ||
                            screen == 'recovery'
                        ? null
                        : MerchantShop(
                            id: 'fixture',
                            name: variant.km ? 'ហាងកាហ្វេកេសរ' : 'Kesor Coffee',
                            active:
                                screen != 'restricted' &&
                                screen != 'pending-review',
                          ),
                  ),
                );
                await pending;
              }
            }
            final name = variant.km ? 'ហាងកាហ្វេកេសរ' : 'Kesor Coffee';
            final gateway = FakeShopGateway()
              ..serverNow = businessToday().add(const Duration(hours: 3));
            if (!screen.startsWith('registration') && screen != 'recovery') {
              gateway.profile = readyProfile(
                name: name,
                status: switch (screen) {
                  'restricted' => 'SUSPENDED',
                  'pending-review' => 'PENDING',
                  _ => 'ACTIVE',
                },
              );
            }
            if (screen.startsWith('owner-transfer')) {
              gateway.profile = fundedProfile();
            }
            // Live collection screens keep second timers running; settle by time.
            final live = screen.startsWith('request-');
            if ({
              'home',
              'sales',
              'wallet',
              'receipt',
              'reports-day',
              'reports-month',
              'requests',
            }.contains(screen)) {
              final made = await gateway.createRequest(
                'qa-${'k' * 20}',
                currency: 'KHR',
                amount: '25000',
                orderReference: variant.km ? 'តុលេខ ៤' : 'Table 4',
              );
              gateway.pay(made.id);
            }
            if (screen == 'requests') {
              await gateway.createRequest(
                'wait-${'k' * 20}',
                currency: 'USD',
                amount: '3.50',
              );
              final closed = await gateway.createRequest(
                'closed-${'k' * 20}',
                currency: 'KHR',
                amount: '1000',
              );
              await gateway.cancelRequest(closed.id);
            }
            final store = MemoryHandoffStore();
            if (screen == 'registration-saved') {
              store.values['registration-1'] = jsonEncode({
                'key': 'k' * 43,
                'draft': ShopDraft(
                  storeName: name,
                  categoryCode: 'FOOD_DRINK',
                  phone: '012 345 678',
                  city: 'Phnom Penh',
                  address: variant.km ? 'ផ្លូវ ៥១ ដូនពេញ' : 'St. 51, Daun Penh',
                ).toJson(),
              });
            }
            final key = GlobalKey();
            await tester.pumpWidget(
              RepaintBoundary(
                key: key,
                child: MerchantApp(
                  preferences: prefs,
                  session: session,
                  shopGateway: screen == 'unavailable' ? null : gateway,
                  shopStore: store,
                  alertEffects: const _Silent(),
                  transferNative: const _FixtureNative(),
                ),
              ),
            );
            if (screen == 'waiting') {
              await tester.pump(const Duration(milliseconds: 300));
            } else {
              await tester.pumpAndSettle();
            }
            if (screen.startsWith('owner-transfer')) {
              await tester.ensureVisible(
                find.byKey(const ValueKey('open-wallet-USD')),
              );
              await tester.pumpAndSettle();
              await tester.tap(find.byKey(const ValueKey('open-wallet-USD')));
              await tester.pumpAndSettle();
              await tester.tap(find.byKey(const ValueKey('wallet-transfer')));
              await tester.pumpAndSettle();
              if (screen != 'owner-transfer-form') {
                await tester.enterText(
                  find.byKey(const ValueKey('transfer-amount-field')),
                  '12.50',
                );
                await tester.tap(find.byKey(const ValueKey('transfer-create')));
                await tester.pump();
                await tester.pump(const Duration(milliseconds: 200));
                if (screen != 'owner-transfer-waiting') {
                  gateway.resolveTransfer(
                    gateway.transfers.keys.single,
                    screen == 'owner-transfer-completed'
                        ? TransferStatus.completed
                        : TransferStatus.failed,
                    failureCode: screen == 'owner-transfer-completed'
                        ? null
                        : 'INSUFFICIENT_FUNDS',
                  );
                  await tester.pump(const Duration(seconds: 2));
                  await tester.pump(const Duration(milliseconds: 200));
                }
              }
            }
            if (screen == 'alert-banner') {
              // A payment to the reusable shop QR arrives while the app is open.
              final made = await gateway.createRequest(
                'qa-${'k' * 20}',
                currency: 'KHR',
                amount: '25000',
              );
              gateway.pay(made.id);
              await tester.pump(const Duration(seconds: 10));
              await tester.pump(const Duration(milliseconds: 300));
            }
            final tab = [
              'home',
              'collect',
              'sales',
              'more',
            ].indexOf(screen == 'sales-empty' ? 'sales' : screen);
            if ({
              'receipt',
              'reports-day',
              'reports-month',
              'requests',
            }.contains(screen)) {
              await tester.tap(find.byType(NavigationDestination).at(2));
              await tester.pumpAndSettle();
              if (screen == 'receipt') {
                await tester.scrollUntilVisible(
                  find.byType(ReceiptRow),
                  200,
                  scrollable: find.byType(Scrollable).first,
                );
                await tester.pumpAndSettle();
                await tester.tap(find.byType(ReceiptRow));
              } else if (screen == 'requests') {
                await tester.tap(find.byKey(const ValueKey('sales-requests')));
              } else {
                await tester.tap(find.byKey(const ValueKey('sales-reports')));
              }
              await tester.pumpAndSettle();
              if (screen == 'reports-month') {
                await tester.tap(find.byKey(const ValueKey('report-MONTH')));
                await tester.pumpAndSettle();
              }
            } else if (screen == 'shop-profile') {
              await tester.tap(find.byType(NavigationDestination).at(3));
              await tester.pumpAndSettle();
              await tester.tap(find.byKey(const ValueKey('open-shop-profile')));
              await tester.pumpAndSettle();
            } else if (tab > 0) {
              await tester.tap(find.byType(NavigationDestination).at(tab));
              await tester.pumpAndSettle();
            } else if (screen == 'wallet') {
              await tester.ensureVisible(
                find.byKey(const ValueKey('open-wallet-KHR')),
              );
              await tester.pumpAndSettle();
              await tester.tap(find.byKey(const ValueKey('open-wallet-KHR')));
              await tester.pumpAndSettle();
            } else if (screen == 'collect-shop-qr') {
              await tester.tap(find.byType(NavigationDestination).at(1));
              await tester.pumpAndSettle();
              await tester.tap(find.byKey(const ValueKey('collect-mode')));
              await tester.tap(find.byIcon(Icons.qr_code_2_rounded).last);
              await tester.pumpAndSettle();
            } else if (live) {
              await tester.tap(find.byType(NavigationDestination).at(1));
              await tester.pumpAndSettle();
              await tester.enterText(
                find.byKey(const ValueKey('collect-amount')),
                '25000',
              );
              await tester.enterText(
                find.byKey(const ValueKey('collect-order')),
                variant.km ? 'តុលេខ ៤' : 'Table 4',
              );
              await tester.ensureVisible(
                find.byKey(const ValueKey('collect-create')),
              );
              await tester.pumpAndSettle();
              await tester.tap(find.byKey(const ValueKey('collect-create')));
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 200));
              if (screen == 'request-paid') {
                gateway.pay(gateway.requests.keys.single);
                await tester.pump(const Duration(seconds: 2));
                await tester.pump(const Duration(milliseconds: 200));
              } else if (screen == 'request-cancelled') {
                await tester.ensureVisible(
                  find.byKey(const ValueKey('request-cancel')),
                );
                await tester.pump();
                await tester.tap(find.byKey(const ValueKey('request-cancel')));
                await tester.pump();
                await tester.pump(const Duration(milliseconds: 200));
              }
              // Back to the top without a pull-to-refresh gesture.
              tester
                  .state<ScrollableState>(find.byType(Scrollable).first)
                  .position
                  .jumpTo(0);
              await tester.pump(const Duration(milliseconds: 500));
            }
            expect(
              tester.takeException(),
              isNull,
              reason: '$screen-${variant.name}-${brightness.name}',
            );
            await renderFixture(
              tester,
              key,
              '$screen-${variant.name}-${brightness.name}',
            );
            // Reach lower form/settings content and catch overflow there too.
            if (screen != 'waiting' &&
                find.byType(Scrollable).evaluate().isNotEmpty) {
              await tester.drag(
                find.byType(Scrollable).first,
                const Offset(0, -2000),
              );
              if (live ||
                  screen == 'owner-transfer-waiting' ||
                  screen == 'owner-transfer-completed' ||
                  screen == 'owner-transfer-failed') {
                await tester.pump(const Duration(milliseconds: 500));
              } else {
                await tester.pumpAndSettle();
              }
              expect(tester.takeException(), isNull);
              if (variant.name == 'phone' &&
                  {
                    'sales',
                    'sales-empty',
                    'receipt',
                    'reports-day',
                    'reports-month',
                    'requests',
                    'more',
                    'collect-shop-qr',
                  }.contains(screen)) {
                await renderFixture(
                  tester,
                  key,
                  '$screen-${variant.name}-${brightness.name}-bottom',
                );
              }
            }
            await tester.pumpWidget(const SizedBox.shrink());
            session.dispose();
            prefs.dispose();
          }
        }
      }
    },
  );
}

/// Platform channels do not answer under the test clock; the fixture has no peer app.
class _FixtureNative extends NativeHandoff {
  const _FixtureNative();
  @override
  Future<String?> takeTransfer() async => null;
  @override
  Future<void> openTransfer(String uri) async {}
}

class _Silent implements AlertEffects {
  const _Silent();
  @override
  void chime() {}
  @override
  void vibrate() {}
}

Future<void> renderFixture(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('.local/qa/m8/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
