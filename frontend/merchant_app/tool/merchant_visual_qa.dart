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

import '../test/merchant_foundation_test.dart' show ControlledMerchantAuth;

void main() {
  testWidgets(
    'M1 screens adapt across language, theme, size and accessibility',
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
            'more',
            'recovery',
            if (variant.name == 'phone') ...[
              'waiting',
              'restricted',
              'unavailable',
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
                    shop: screen == 'registration' || screen == 'recovery'
                        ? null
                        : MerchantShop(
                            id: 'fixture',
                            name: variant.km ? 'ហាងកាហ្វេកេសរ' : 'Kesor Coffee',
                            active: screen != 'restricted',
                          ),
                  ),
                );
                await pending;
              }
            }
            final key = GlobalKey();
            await tester.pumpWidget(
              RepaintBoundary(
                key: key,
                child: MerchantApp(preferences: prefs, session: session),
              ),
            );
            if (screen == 'waiting') {
              await tester.pump(const Duration(milliseconds: 300));
            } else {
              await tester.pumpAndSettle();
            }
            final tab = ['home', 'collect', 'sales', 'more'].indexOf(screen);
            if (tab > 0) {
              await tester.tap(find.byType(NavigationDestination).at(tab));
              await tester.pumpAndSettle();
            }
            expect(
              tester.takeException(),
              isNull,
              reason: '$screen-${variant.name}-${brightness.name}',
            );
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                '.local/qa/m1/$screen-${variant.name}-${brightness.name}.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
            // Reach lower form/settings content and catch overflow there too.
            if (screen != 'waiting' &&
                find.byType(Scrollable).evaluate().isNotEmpty) {
              await tester.drag(
                find.byType(Scrollable).first,
                const Offset(0, -2000),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
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
