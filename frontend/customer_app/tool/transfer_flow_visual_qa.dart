// Controlled design data only. This fixture never calls a banking gateway.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/features/transactions/presentation/transfer_review_screen.dart';
import 'package:customer_app/features/transactions/presentation/transfer_success_screen.dart';
import 'package:customer_app/features/transactions/transfer_models.dart';
import 'package:customer_app/shared/money.dart';
import 'package:customer_app/shared/widgets/kesor_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'review, receipt and bottom bar match Figma and adapt to device text',
    (tester) async {
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = true);
      await tester.runAsync(() async {
        for (final entry in {
          'Poppins': [
            'Poppins-Light.ttf',
            'Poppins-Regular.ttf',
            'Poppins-Medium.ttf',
            'Poppins-SemiBold.ttf',
            'Poppins-Bold.ttf',
          ],
          'Google Sans': [
            'GoogleSans-Regular.ttf',
            'GoogleSans-Medium.ttf',
            'GoogleSans-Bold.ttf',
          ],
          'Noto Sans Khmer': ['NotoSansKhmer-Variable.ttf'],
        }.entries) {
          final loader = FontLoader(entry.key);
          for (final file in entry.value) {
            loader.addFont(rootBundle.load('assets/fonts/$file'));
          }
          await loader.load();
        }
      });
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final draft = TransferDraft(
        '1000000001',
        '123 123 135',
        Money.parse('25.00', 'USD'),
        null,
        destinationName: 'Sok Dara',
      );
      final saved = SavedTransfer(
        key: 'fixture-confirmed',
        draft: draft,
        createdAt: DateTime(2026, 10, 30, 9, 41),
        outcome: 'success',
        reference: 'KSR261030000128',
      );
      for (final variant in [
        (
          name: 'reference-en',
          width: 440.0,
          height: 956.0,
          scale: 1.0,
          km: false,
        ),
        (
          name: 'reference-km',
          width: 440.0,
          height: 956.0,
          scale: 1.0,
          km: true,
        ),
        (name: 'small-en', width: 375.0, height: 667.0, scale: 1.0, km: false),
        (name: 'native-en', width: 393.0, height: 852.0, scale: 1.3, km: false),
        (name: 'native-km', width: 393.0, height: 852.0, scale: 1.3, km: true),
        (
          name: 'long-details',
          width: 375.0,
          height: 812.0,
          scale: 1.3,
          km: false,
        ),
        (
          name: 'reference-khr',
          width: 440.0,
          height: 956.0,
          scale: 1.0,
          km: false,
        ),
        (name: 'large-km', width: 320.0, height: 667.0, scale: 2.0, km: true),
        (
          name: 'landscape-en',
          width: 812.0,
          height: 375.0,
          scale: 2.0,
          km: false,
        ),
        (
          name: 'tablet-en',
          width: 800.0,
          height: 1280.0,
          scale: 1.3,
          km: false,
        ),
      ]) {
        for (final dark in [false, true]) {
          final fixtureDraft = variant.name == 'long-details'
              ? TransferDraft(
                  draft.source,
                  '12345678901234567890',
                  Money.parse('9999999.99', 'USD'),
                  'Payment for family expenses and this month’s household supplies.',
                  destinationName: 'Sok Dara and family household account',
                )
              : variant.name == 'reference-khr'
              ? TransferDraft(
                  draft.source,
                  draft.destination,
                  Money.parse('10000', 'KHR'),
                  null,
                  destinationName: draft.destinationName,
                )
              : draft;
          final fixtureSaved = SavedTransfer(
            key: saved.key,
            draft: fixtureDraft,
            createdAt: saved.createdAt,
            outcome: saved.outcome,
            reference: saved.reference,
          );
          final walletName = fixtureDraft.amount.currency == 'KHR'
              ? (variant.km ? 'កាបូបប្រាក់រៀល' : 'Khmer Riel Wallet')
              : (variant.km ? 'កាបូបប្រាក់ដុល្លារអាមេរិក' : 'US Dollar Wallet');
          final prefs = AppPreferences()
            ..locale = Locale(variant.km ? 'km' : 'en');
          for (final screen in ['review', 'success', 'navigation']) {
            final size = Size(variant.width, variant.height);
            final native = variant.name.startsWith('native');
            var homeTapped = false, anotherTapped = false;
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            final key = GlobalKey();
            final theme = AppTheme.build(
              dark ? Brightness.dark : Brightness.light,
              locale: prefs.locale,
            );
            await tester.pumpWidget(
              AppPreferencesScope(
                preferences: prefs,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  locale: prefs.locale,
                  supportedLocales: const [Locale('en'), Locale('km')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: theme,
                  home: MediaQuery(
                    data: MediaQueryData(
                      size: size,
                      textScaler: TextScaler.linear(variant.scale),
                      disableAnimations: true,
                      padding: native
                          ? const EdgeInsets.only(top: 24, bottom: 34)
                          : EdgeInsets.zero,
                    ),
                    child: RepaintBoundary(
                      key: key,
                      child: screen == 'review'
                          ? KesorTransferReviewScreen(
                              draft: fixtureDraft,
                              walletName: walletName,
                              saveFavorite: false,
                              onEdit: () {},
                              onConfirm: () {},
                              messages: const SizedBox.shrink(),
                              busy: false,
                              showDeviceChrome: !native,
                            )
                          : screen == 'success'
                          ? KesorTransferSuccessScreen(
                              saved: fixtureSaved,
                              walletName: walletName,
                              completedAt: DateTime(2026, 10, 30, 9, 41),
                              onHome: () => homeTapped = true,
                              onAnother: () => anotherTapped = true,
                              messages: variant.name == 'long-details'
                                  ? const Text(
                                      'Balance refresh unavailable. Your transfer is complete.',
                                    )
                                  : const SizedBox.shrink(),
                              showDeviceChrome: !native,
                            )
                          : Scaffold(
                              body: SingleChildScrollView(
                                child: Center(
                                  child: SizedBox(
                                    width: size.width.clamp(0, 440) - 40,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        for (
                                          var selected = 0;
                                          selected < 4;
                                          selected++
                                        ) ...[
                                          KesorBottomBar(
                                            selectedIndex: selected,
                                            onSelected: (_) {},
                                            onAssistant: () {},
                                          ),
                                          const SizedBox(height: 24),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.runAsync(() async {
              for (final asset in [
                'assets/transfer/flag-us.png',
                'assets/transfer/receipt-perforation.png',
                'assets/transfer/success-seal.png',
              ]) {
                await precacheImage(AssetImage(asset), key.currentContext!);
              }
            });
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$screen ${variant.name} dark=$dark',
            );
            if (screen == 'success') {
              expect(find.byType(SingleChildScrollView), findsNothing);
              Rect bounds(String key) =>
                  tester.getRect(find.byKey(ValueKey(key)));
              for (final target in [
                'transfer-success-seal',
                'transfer-success-title',
                'transfer-success-amount',
                'transfer-success-receipt',
                'transfer-back-home',
                'transfer-another',
              ]) {
                final rect = bounds(target);
                expect(rect.left, greaterThanOrEqualTo(0), reason: target);
                expect(
                  rect.right,
                  lessThanOrEqualTo(size.width),
                  reason: target,
                );
                expect(
                  rect.top,
                  greaterThanOrEqualTo(native ? 24 : 54),
                  reason: target,
                );
                expect(
                  rect.bottom,
                  lessThanOrEqualTo(size.height - (native ? 34 : 0)),
                  reason: target,
                );
              }
              expect(
                bounds('transfer-success-receipt').bottom,
                lessThanOrEqualTo(bounds('transfer-back-home').top),
              );
              for (final target in ['transfer-back-home', 'transfer-another']) {
                expect(bounds(target).height, greaterThanOrEqualTo(48));
              }
              await tester.tap(
                find.byKey(const ValueKey('transfer-back-home')),
              );
              await tester.tap(find.byKey(const ValueKey('transfer-another')));
              expect(homeTapped, isTrue);
              expect(anotherTapped, isTrue);
              await tester.pumpAndSettle();
            }
            if (screen != 'navigation') {
              expect(
                find.byKey(
                  ValueKey(
                    'transfer-currency-flag-${fixtureDraft.amount.currency}',
                  ),
                ),
                findsOneWidget,
              );
            }
            if (variant.name == 'reference-en' && !dark) {
              if (screen == 'navigation') {
                expect(
                  tester.getSize(
                    find.byKey(const ValueKey('kesor-nav-capsule')).first,
                  ),
                  const Size(320, 64),
                );
                expect(
                  tester.getSize(
                    find.byKey(const ValueKey('bottom-tab-0')).first,
                  ),
                  const Size(104, 56),
                );
              } else if (screen == 'review') {
                for (final target in {
                  'transfer-review-emblem': const Offset(184, 138),
                  'transfer-review-panel': const Offset(0, 288),
                  'transfer-review-accounts': const Offset(24, 430),
                  'transfer-review-reminder': const Offset(24, 693),
                  'transfer-confirm': const Offset(24, 866),
                }.entries) {
                  expect(
                    tester.getTopLeft(find.byKey(ValueKey(target.key))).dx,
                    closeTo(target.value.dx, 1),
                    reason: target.key,
                  );
                  expect(
                    tester.getTopLeft(find.byKey(ValueKey(target.key))).dy,
                    closeTo(target.value.dy, 1),
                    reason: target.key,
                  );
                }
                expect(
                  tester.getSize(
                    find.byKey(const ValueKey('transfer-confirm')),
                  ),
                  const Size(392, 54),
                );
              } else if (screen == 'success') {
                for (final target in {
                  'transfer-success-seal': const Offset(146, 68),
                  'transfer-success-receipt': const Offset(32, 394),
                  'transfer-back-home': const Offset(32, 808),
                  'transfer-another': const Offset(32, 872),
                }.entries) {
                  expect(
                    tester.getTopLeft(find.byKey(ValueKey(target.key))).dx,
                    closeTo(target.value.dx, 1),
                    reason: target.key,
                  );
                  expect(
                    tester.getTopLeft(find.byKey(ValueKey(target.key))).dy,
                    closeTo(target.value.dy, 1),
                    reason: target.key,
                  );
                }
                expect(
                  tester.getSize(
                    find.byKey(const ValueKey('transfer-success-receipt')),
                  ),
                  const Size(376, 366),
                );
              }
            }
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                '.local/qa/transfer-flow/$screen-${variant.name}-${dark ? 'dark' : 'light'}.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
            await tester.pumpWidget(const SizedBox.shrink());
          }
          prefs.dispose();
        }
      }
      debugDisableShadows = true;
    },
  );
}
