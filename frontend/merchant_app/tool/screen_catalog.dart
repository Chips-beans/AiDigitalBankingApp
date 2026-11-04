import '../test/support/merchant_navigation.dart';

// Renders every Merchant App screen in light mode and English at phone size
// into `<repo>/Flutter Screen/Merchant App`. Controlled fixture data only.
//
//   flutter test tool/screen_catalog.dart --concurrency=1
//
// Set SCREEN_ONLY=welcome,home to render a subset while iterating.
// Set SCREEN_OUTPUT_DIR to export a new catalog without replacing an earlier one.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart' as vector;
import 'package:kesor_auth_handoff/kesor_auth_handoff.dart';
import 'package:merchant_app/app/merchant_app.dart';
import 'package:merchant_app/core/merchant_preferences.dart';
import 'package:merchant_app/features/auth/merchant_session.dart';
import 'package:merchant_app/features/collect/merchant_collect.dart';
import 'package:merchant_app/features/collect/wallet_page.dart' show ReceiptRow;
import 'package:merchant_app/features/feed/payment_feed_controller.dart';
import 'package:merchant_app/features/shop/merchant_shop.dart';
import 'package:merchant_app/features/transfer/owner_transfer.dart'
    show TransferStatus;

import '../test/merchant_foundation_test.dart' show ControlledMerchantAuth;
import '../test/merchant_shop_test.dart' show FakeShopGateway;
import '../test/merchant_transfer_test.dart' show fundedProfile;

/// (id used by the driver, readable file name, extra scrolled capture allowed).
const _screens = <(String, String)>[
  ('welcome', '01_Welcome_Continue_With_Kesor_Bank'),
  ('waiting', '02_Sign_In_Waiting_For_Approval'),
  ('unavailable', '03_Sign_In_Service_Unavailable'),
  ('registration', '04_Register_Shop'),
  ('registration-saved', '05_Register_Shop_Saved_Draft'),
  ('recovery', '06_Account_Recovery_Required'),
  ('home', '07_Home'),
  ('wallet', '08_Wallet_Details'),
  ('collect', '09_Collect_Enter_Amount'),
  ('request-waiting', '10_Collect_Waiting_For_Payment'),
  ('request-paid', '11_Collect_Payment_Received'),
  ('request-cancelled', '12_Collect_Request_Cancelled'),
  ('collect-shop-qr', '13_Collect_Shop_QR'),
  ('sales', '14_Sales'),
  ('sales-empty', '15_Sales_Empty'),
  ('receipt', '16_Sales_Receipt'),
  ('reports-day', '17_Reports_Daily'),
  ('reports-month', '18_Reports_Monthly'),
  ('requests', '19_Payment_Requests_History'),
  ('more', '20_More_Settings'),
  ('shop-profile', '21_Shop_Profile_Edit'),
  ('owner-transfer-form', '22_Owner_Transfer_Enter_Amount'),
  ('owner-transfer-waiting', '23_Owner_Transfer_Waiting_For_Approval'),
  ('owner-transfer-completed', '24_Owner_Transfer_Completed'),
  ('owner-transfer-failed', '25_Owner_Transfer_Failed_Insufficient_Funds'),
  ('alert-banner', '26_Payment_Alert_Banner'),
  ('restricted', '27_Shop_Suspended_Restricted'),
  ('pending-review', '28_Shop_Pending_Review'),
  ('side-menu', '29_Side_Menu'),
  ('appearance', '30_Language_And_Appearance'),
  ('payment-alerts', '31_Payment_Alerts'),
  ('sign-out', '32_Sign_Out_Confirmation'),
  ('request-expired', '33_Request_Expired'),
  ('denied', '34_Sign_In_Declined'),
];

const _size = Size(393, 852);
const _shot = 3.0;

void main() {
  testWidgets('Merchant screen catalog (light, English, phone)', (
    tester,
  ) async {
    final only = (Platform.environment['SCREEN_ONLY'] ?? '')
        .split(',')
        .where((e) => e.isNotEmpty)
        .toSet();
    final out = Directory(
      Platform.environment['SCREEN_OUTPUT_DIR'] ??
          '${Directory.current.absolute.parent.parent.path}/Flutter Screen/Merchant App',
    )..createSync(recursive: true);
    // Real shadows, like a device. Restored at the end (the binding checks it
    // before tear-downs run).
    debugDisableShadows = false;
    await tester.runAsync(() async {
      for (final entry in {
        'MaterialIcons': ['fonts/MaterialIcons-Regular.otf'],
        'Poppins': [
          'assets/fonts/Poppins-Regular.ttf',
          'assets/fonts/Poppins-Medium.ttf',
          'assets/fonts/Poppins-SemiBold.ttf',
          'assets/fonts/Poppins-Light.ttf',
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
    // Warm exported SVG bytecode outside the fake clock before captures.
    await tester.runAsync(() async {
      for (final file in Directory(
        'assets/figma',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.svg'))) {
        await vector.SvgAssetLoader(
          'assets/figma/${file.uri.pathSegments.last}',
        ).loadBytes(null);
      }
    });
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    tester.platformDispatcher.textScaleFactorTestValue = 1.0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = _size;
    // Android status bar and gesture navigation insets.
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 20);

    final written = <String>[];
    for (final (screen, fileName) in _screens) {
      if (only.isNotEmpty && !only.contains(screen)) continue;
      final prefs = MerchantPreferences()
        ..setLanguage('en')
        ..setTheme(ThemeMode.light);
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
        } else if (screen == 'denied') {
          auth.approval.completeError(
            const MerchantAuthFailure(MerchantAuthIssue.denied),
          );
          await pending;
        } else {
          auth.approval.complete(
            MerchantIdentity(
              ownerId: 1,
              recoveryRequired: screen == 'recovery',
              shop: screen.startsWith('registration') || screen == 'recovery'
                  ? null
                  : MerchantShop(
                      id: 'fixture',
                      name: 'Kesor Coffee',
                      active:
                          screen != 'restricted' && screen != 'pending-review',
                    ),
            ),
          );
          await pending;
        }
      }
      final gateway = FakeShopGateway()
        ..serverNow = businessToday().add(const Duration(hours: 3));
      if (!screen.startsWith('registration') && screen != 'recovery') {
        // Funded wallets so balances look like a shop that has been trading.
        gateway.profile = fundedProfile(
          status: switch (screen) {
            'restricted' => 'SUSPENDED',
            'pending-review' => 'PENDING',
            _ => 'ACTIVE',
          },
        );
      }
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
          orderReference: 'Table 4',
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
            storeName: 'Kesor Coffee',
            categoryCode: 'FOOD_DRINK',
            phone: '012 345 678',
            city: 'Phnom Penh',
            address: 'St. 51, Daun Penh',
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
        await tester.pumpAndSettle();
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
        await openMerchantSection(tester, 2);
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
          await openMerchantMenu(tester, 'dc524');
        } else {
          await openMerchantMenu(tester, '8b848');
        }
        await tester.pumpAndSettle();
        if (screen == 'reports-month') {
          await tester.tap(find.text('Monthly'));
          await tester.pumpAndSettle();
        }
      } else if (screen == 'shop-profile') {
        await openMerchantSection(tester, 3);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('open-shop-profile')));
        await tester.pumpAndSettle();
      } else if (tab > 0) {
        await openMerchantSection(tester, tab);
        await tester.pumpAndSettle();
      } else if (screen == 'wallet') {
        await tester.ensureVisible(
          find.byKey(const ValueKey('open-wallet-KHR')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('open-wallet-KHR')));
        await tester.pumpAndSettle();
      } else if (screen == 'side-menu') {
        await tester.tap(find.byKey(const ValueKey('merchant-menu')));
        await tester.pumpAndSettle();
      } else if ({
        'appearance',
        'payment-alerts',
        'sign-out',
      }.contains(screen)) {
        await openMerchantSection(tester, 3);
        final item = find.byKey(
          ValueKey(
            screen == 'appearance'
                ? 'more-language'
                : screen == 'payment-alerts'
                ? 'more-alerts'
                : 'more-signout',
          ),
        );
        await tester.scrollUntilVisible(
          item,
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(item);
        await tester.pumpAndSettle();
      } else if (screen == 'collect-shop-qr') {
        await openMerchantSection(tester, 1);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Shop QR'));
        await tester.pumpAndSettle();
      } else if (live) {
        await openMerchantSection(tester, 1);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('collect-amount')),
          '25000',
        );
        await tester.enterText(
          find.byKey(const ValueKey('collect-order')),
          'Table 4',
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
        } else if (screen == 'request-expired') {
          final id = gateway.requests.keys.single,
              old = gateway.requests.values.single;
          gateway.requests[id] = PaymentRequest(
            id: id,
            reference: old.reference,
            status: RequestStatus.expired,
            currency: old.currency,
            amount: old.amount,
            orderReference: old.orderReference,
            expiresAt: old.expiresAt,
            serverTime: old.serverTime,
          );
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
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pump(const Duration(milliseconds: 500));
      }
      if (screen == 'collect') {
        await tester.enterText(
          find.byKey(const ValueKey('collect-amount')),
          '25000',
        );
        await tester.pump();
      }
      expect(tester.takeException(), isNull, reason: screen);
      written.add((await _shoot(tester, key, out, fileName))!);

      // Content below the fold gets a second, scrolled capture (vertical only;
      // a horizontal chip row must never be mistaken for the page scroller).
      if (screen != 'waiting' && screen != 'sign-out') {
        final vertical = find
            .byType(Scrollable)
            .evaluate()
            .map((e) => (e as StatefulElement).state as ScrollableState)
            .where((s) => s.position.axis == Axis.vertical)
            .toList();
        if (vertical.isNotEmpty &&
            vertical.last.position.maxScrollExtent > 60) {
          final position = vertical.last.position;
          position.jumpTo(position.maxScrollExtent);
          if (live || screen.startsWith('owner-transfer')) {
            await tester.pump(const Duration(milliseconds: 500));
          } else {
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull, reason: '$screen scrolled');
          final second = await _shoot(
            tester,
            key,
            out,
            '${fileName}_2_Scrolled',
            sameAs: written.last,
          );
          if (second != null) written.add(second);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      prefs.dispose();
    }
    debugDisableShadows = true;
    // ignore: avoid_print
    print('Wrote ${written.length} screenshots to ${out.path}');
  });
}

/// Platform channels do not answer under the test clock; there is no peer app.
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

/// Writes the PNG, or returns null when it would equal the file at [sameAs].
Future<String?> _shoot(
  WidgetTester tester,
  GlobalKey key,
  Directory out,
  String name, {
  String? sameAs,
}) async {
  final path = '${out.path}/$name.png';
  var skipped = false;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _shot);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = data!.buffer.asUint8List();
      if (sameAs != null && await File(sameAs).exists()) {
        final previous = await File(sameAs).readAsBytes();
        if (previous.length == bytes.length &&
            Iterable<int>.generate(bytes.length)
                .every((i) => previous[i] == bytes[i])) {
          skipped = true;
          return;
        }
      }
      await File(path).writeAsBytes(bytes);
    } finally {
      image.dispose();
    }
  });
  return skipped ? null : path;
}
