import 'dart:io';
import 'dart:ui' as ui;

import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/features/auth/presentation/app_pin_page.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('render three Figma PIN frames and adaptive variants', (
    tester,
  ) async {
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
    for (final variant in [
      (name: 'reference-en', size: const Size(440, 999), scale: 1.0, km: false),
      (name: 'reference-km', size: const Size(440, 999), scale: 1.0, km: true),
      (name: 'small', size: const Size(375, 812), scale: 1.0, km: false),
      (name: 'large-text', size: const Size(320, 568), scale: 2.0, km: false),
      (name: 'large-text-km', size: const Size(375, 667), scale: 2.0, km: true),
      (name: 'landscape', size: const Size(812, 375), scale: 1.0, km: false),
      (name: 'tablet', size: const Size(1024, 768), scale: 1.0, km: false),
    ]) {
      tester.view.physicalSize = variant.size;
      tester.view.devicePixelRatio = 1;
      final prefs = AppPreferences()..locale = Locale(variant.km ? 'km' : 'en');
      for (final mode in [PinStage.create, PinStage.confirm, PinStage.unlock]) {
        final key = GlobalKey();
        await tester.pumpWidget(
          AppPreferencesScope(
            preferences: prefs,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: prefs.locale,
              supportedLocales: const [Locale('en'), Locale('km')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: AppTheme.build(Brightness.light, locale: prefs.locale),
              home: MediaQuery(
                data: MediaQueryData(
                  size: variant.size,
                  textScaler: TextScaler.linear(variant.scale),
                  disableAnimations: true,
                ),
                child: RepaintBoundary(
                  key: key,
                  child: PinScreen(
                    stage: mode,
                    name: 'Seng Sovanreach',
                    showDeviceChrome: true,
                    onNumber: (_) {},
                    onClear: () {},
                    onDelete: () {},
                    onForgot: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${mode.name}-${variant.name}',
        );
        if (variant.name == 'reference-en') {
          expect(
            tester.getTopLeft(find.byKey(const ValueKey('pin-avatar'))),
            const Offset(180, 86),
          );
          expect(
            tester.getSize(find.byKey(const ValueKey('pin-digit-1'))),
            const Size(100, 100),
          );
          expect(
            tester.getTopLeft(find.byKey(const ValueKey('pin-digit-1'))),
            Offset(42, mode == PinStage.unlock ? 384 : 412),
          );
        }
        Future<void> capture(String suffix) async => tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          final file = File(
            '.local/qa/pin/${mode.name}-${variant.name}$suffix.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
        });
        await capture('');
        await tester.ensureVisible(find.byKey(const ValueKey('pin-digit-0')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (variant.scale > 1 || variant.size.height < 600) {
          await capture('-bottom');
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
      prefs.dispose();
    }
  });
}
