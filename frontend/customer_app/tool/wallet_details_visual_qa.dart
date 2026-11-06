import 'dart:io';
import 'dart:ui' as ui;

import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/features/accounts/account_gateway.dart';
import 'package:customer_app/shared/money.dart';
import 'package:customer_app/features/accounts/presentation/wallet_accounts_screen.dart';
import 'package:customer_app/features/accounts/presentation/wallet_detail_screen.dart';
import 'package:customer_app/features/transactions/presentation/transaction_detail_screen.dart';
import 'package:customer_app/shared/widgets/customer_splash.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/analytics_test.dart' show loadAnalyticsFonts;
import '../test/wallet_details_design_test.dart';

void main() {
  testWidgets('section 3: wallet, receipt and splash responsive visual matrix', (
    tester,
  ) async {
    await loadAnalyticsFonts(tester);
    await tester.runAsync(() async {
      for (final dir in [
        'assets/wallet-details',
        'assets/splash',
        'assets/figma',
      ]) {
        for (final file in Directory(
          dir,
        ).listSync().whereType<File>().where((f) => f.path.endsWith('.svg'))) {
          await SvgAssetLoader('$dir/${file.uri.pathSegments.last}')
              .loadBytes(null);
        }
      }
    });
    final rig = await DetailRig.create();
    addTearDown(rig.dispose);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var count = 0;
    for (final screen in ['wallets', 'wallet', 'receipt', 'splash']) {
      for (final size in [
        const Size(440, 999),
        const Size(440, 956),
        const Size(393, 852),
        const Size(320, 568),
        const Size(844, 390),
        const Size(800, 1280),
      ]) {
        for (final dark in [false, true]) {
          for (final km in [false, true]) {
            for (final scale in [1.0, 1.3, 2.0]) {
              if (Platform.environment['SECTION3_REFERENCE_ONLY'] == '1' &&
                  (dark ||
                      km ||
                      scale != 1 ||
                      size !=
                          (screen == 'wallets'
                              ? const Size(440, 999)
                              : screen == 'splash'
                              ? const Size(393, 852)
                              : const Size(440, 956)))) {
                continue;
              }
              await rig.accounts.select(
                rig.accounts.accounts.firstWhere(
                  (a) => a.currency == (screen == 'wallet' ? 'KHR' : 'USD'),
                ),
              );
              final currency = rig.accounts.selected!.currency;
              RecentPosting sample(
                String ref,
                String amount,
                DateTime date, {
                String? operation,
                bool incoming = false,
                String name = 'SENG SOVANREACH',
              }) => RecentPosting(
                reference: ref,
                source: incoming ? '0965160110' : rig.accounts.selected!.number,
                destination: incoming
                    ? rig.accounts.selected!.number
                    : '0965160110',
                amount: Money.parse(amount, currency),
                fee: Money.parse('0', currency),
                type: 'TRANSFER',
                status: 'SUCCESS',
                createdAt: date,
                sourceName: name,
                destinationName: name,
                operation: operation,
              );
              rig.api.historyItems = currency == 'KHR'
                  ? [
                      sample(
                        'KSR-SEPT-13',
                        '1947',
                        DateTime.utc(2026, 9, 13, 12),
                      ),
                      sample(
                        'KSR-SEPT-05-A',
                        '4056',
                        DateTime.utc(2026, 9, 5, 12),
                        operation: 'MERCHANT_PAYMENT',
                        name: 'Smart',
                      ),
                      sample(
                        'KSR-SEPT-05-B',
                        '4000',
                        DateTime.utc(2026, 9, 5, 10),
                        operation: 'QR_PAYMENT',
                        incoming: true,
                        name: 'SOKUNBANHA KAY',
                      ),
                      sample(
                        'KSR-SEPT-04',
                        '2000',
                        DateTime.utc(2026, 9, 4, 12),
                        operation: 'QR_PAYMENT',
                        incoming: true,
                        name: 'OKNHA SAMAUN',
                      ),
                    ]
                  : [
                      detailPosting(currency),
                      sample(
                        'KSR261103000129',
                        '5.00',
                        DateTime.utc(2026, 11, 3, 12),
                        operation: 'QR_PAYMENT',
                      ),
                    ];
              await rig.history.refresh();
              await rig.history.openDetail(
                rig.api.historyItems.first.reference,
              );
              tester.view.physicalSize = size;
              final prefs = AppPreferences()..locale = Locale(km ? 'km' : 'en');
              final boundary = GlobalKey();
              final reference = size.width == 440 && scale == 1 && !km && !dark;
              final inset = screen == 'splash'
                  ? EdgeInsets.zero
                  : EdgeInsets.only(
                      top: reference ? 44 : 24,
                      bottom: reference ? 0 : 24,
                    );
              final owner = km
                  ? 'សេង សុវណ្ណរាជ'
                  : scale == 2
                  ? 'SENG SOVANREACH LONG CUSTOMER NAME'
                  : 'SENG SOVANREACH';
              final child = switch (screen) {
                'wallets' => WalletAccountsScreen(
                  model: rig.accounts,
                  greetingName: owner,
                  onBack: () {},
                  onProfile: () {},
                  onRefresh: rig.accounts.refresh,
                  onTransfer: () {},
                  onMyQr: () {},
                  onOpenAccounts: () {},
                  onDetails: () {},
                  onActivity: () {},
                  bottomBar: const SizedBox(),
                ),
                'wallet' => WalletDetailScreen(
                  accounts: rig.accounts,
                  history: rig.history,
                  ownerName: owner,
                  onBack: () {},
                  onTransaction: (_) {},
                ),
                'receipt' => TransactionDetailScreen(
                  accounts: rig.accounts,
                  history: rig.history,
                  reference: rig.api.historyItems.first.reference,
                  ownerName: owner,
                  onBack: () {},
                ),
                _ => const CustomerSplash(animate: false),
              };
              await tester.pumpWidget(
                detailsHarness(
                  RepaintBoundary(key: boundary, child: child),
                  preferences: prefs,
                  size: size,
                  scale: scale,
                  dark: dark,
                  padding: inset,
                ),
              );
              await tester.pumpAndSettle();
              final label =
                  '$screen-${size.width.toInt()}x${size.height.toInt()}-${dark ? 'dark' : 'light'}-${km ? 'km' : 'en'}-$scale';
              expect(tester.takeException(), isNull, reason: label);
              if (screen == 'receipt') {
                final actions = find.byKey(const ValueKey('receipt-download'));
                await tester.ensureVisible(actions);
                await tester.pumpAndSettle();
                expect(
                  tester.getSize(actions).height,
                  greaterThanOrEqualTo(48),
                  reason: label,
                );
                final scroll = tester.state<ScrollableState>(
                  find
                      .descendant(
                        of: find.byKey(const ValueKey('receipt-scroll')),
                        matching: find.byType(Scrollable),
                      )
                      .first,
                );
                scroll.position.jumpTo(0);
                await tester.pump();
              }
              await tester.runAsync(() async {
                final render =
                    boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final image = await render.toImage(pixelRatio: 1);
                final png = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final dir = Directory('.local/qa/section3')
                  ..createSync(recursive: true);
                File('${dir.path}/$label.png')
                    .writeAsBytesSync(png!.buffer.asUint8List());
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
    print('Section 3: $count responsive renders; no layout exceptions.');
  });
}
