import 'dart:io';
import 'dart:ui' as ui;

import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/features/accounts/presentation/wallet_detail_screen.dart';
import 'package:customer_app/features/transactions/history_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/analytics_test.dart' show loadAnalyticsFonts;
import '../test/merchant_wallets_test.dart';
import '../test/transactions_test.dart' show FakeTransactions;
import '../test/wallet_details_design_test.dart' show detailsHarness;

void main() {
  testWidgets('linked merchant wallets responsive states', (tester) async {
    await loadAnalyticsFonts(tester);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final linked = await MerchantWalletRig.create();
    final unlinked = await MerchantWalletRig.create(linked: false);
    final history = HistoryController(
      linked.session,
      linked.merchant,
      FakeTransactions(),
    );
    addTearDown(() {
      history.dispose();
      linked.dispose();
      unlinked.dispose();
    });
    await linked.merchant.refresh();
    var count = 0;
    for (final size in [
      const Size(393, 852),
      const Size(320, 568),
      const Size(800, 1280),
    ]) {
      for (final dark in [false, true]) {
        for (final km in [false, true]) {
          for (final scale in [1.0, 2.0]) {
            tester.view.physicalSize = size;
            for (final state in ['unlinked', 'linked', 'business', 'detail']) {
              final rig = state == 'unlinked' ? unlinked : linked;
              final boundary = GlobalKey();
              final prefs = AppPreferences()..locale = Locale(km ? 'km' : 'en');
              final child = state == 'detail'
                  ? WalletDetailScreen(
                      accounts: linked.merchant,
                      history: history,
                      ownerName: km ? 'សុខ ដារ៉ា' : 'Sok Dara',
                      onBack: () {},
                      onTransaction: (_) {},
                    )
                  : rig.screen();
              await tester.pumpWidget(
                detailsHarness(
                  RepaintBoundary(key: boundary, child: child),
                  preferences: prefs,
                  size: size,
                  scale: scale,
                  dark: dark,
                  padding: const EdgeInsets.only(top: 24, bottom: 24),
                ),
              );
              await tester.pumpAndSettle();
              if (state == 'business') {
                await tester.ensureVisible(
                  find.byKey(
                    ValueKey('wallet-tile-${merchantWallet(3).number}'),
                  ),
                );
                await tester.pumpAndSettle();
              }
              final name =
                  '$state-${size.width.toInt()}-${dark ? 'dark' : 'light'}-${km ? 'km' : 'en'}-$scale';
              expect(tester.takeException(), isNull, reason: name);
              await tester.runAsync(() async {
                final render =
                    boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final image = await render.toImage(pixelRatio: 1);
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final dir = Directory('.local/qa/merchant-wallets')
                  ..createSync(recursive: true);
                File('${dir.path}/$name.png')
                    .writeAsBytesSync(bytes!.buffer.asUint8List());
                image.dispose();
              });
              await tester.pumpWidget(const SizedBox());
              count++;
            }
          }
        }
      }
    }
    // ignore: avoid_print
    print('Merchant wallets: $count responsive renders; no layout exceptions.');
  });
}
