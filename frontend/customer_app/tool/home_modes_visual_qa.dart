import 'dart:io';
import 'dart:ui' as ui;

import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/auth/data/auth_gateway.dart';
import 'package:customer_app/features/auth/presentation/continuation_pages.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:customer_app/features/home/presentation/kesor_home_screen.dart';
import 'package:customer_app/shared/widgets/kesor_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'render Figma Home/login modes, languages, navigation states and responsive variants',
    (tester) async {
      await tester.runAsync(() async {
        for (final family in {
          'Google Sans': [
            'GoogleSans-Regular.ttf',
            'GoogleSans-Medium.ttf',
            'GoogleSans-Bold.ttf',
          ],
          'Poppins': [
            'Poppins-Light.ttf',
            'Poppins-Regular.ttf',
            'Poppins-Medium.ttf',
            'Poppins-SemiBold.ttf',
          ],
          'Noto Sans Khmer': ['NotoSansKhmer-Variable.ttf'],
        }.entries) {
          final loader = FontLoader(family.key);
          for (final file in family.value) {
            loader.addFont(rootBundle.load('assets/fonts/$file'));
          }
          await loader.load();
        }
      });
      await tester.runAsync(() async {
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      });
      final session = SessionController(
        DemoAuthGateway(),
        MemorySessionVault(),
      );
      await session.initialize();
      addTearDown(session.dispose);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixtures = [
        for (final dark in [false, true])
          for (final km in [true, false])
            (
              name: 'home-${dark ? 'dark' : 'light'}-${km ? 'km' : 'en'}',
              size: const Size(440, 999),
              scale: 1.0,
              home: true,
              dark: dark,
              km: km,
            ),
        for (final dark in [false, true])
          for (final km in [false, true]) ...[
            (
              name: 'welcome-${dark ? 'dark' : 'light'}-${km ? 'km' : 'en'}',
              size: const Size(440, 956),
              scale: 1.0,
              home: false,
              dark: dark,
              km: km,
            ),
            (
              name:
                  'welcome-small-${dark ? 'dark' : 'light'}-${km ? 'km' : 'en'}',
              size: const Size(320, 568),
              scale: 2.0,
              home: false,
              dark: dark,
              km: km,
            ),
          ],
        for (final dark in [false, true])
          (
            name: 'home-small-${dark ? 'dark' : 'light'}',
            size: const Size(375, 812),
            scale: 1.0,
            home: true,
            dark: dark,
            km: true,
          ),
        (
          name: 'home-large-text',
          size: const Size(375, 667),
          scale: 2.0,
          home: true,
          dark: true,
          km: true,
        ),
        (
          name: 'home-landscape',
          size: const Size(667, 375),
          scale: 2.0,
          home: true,
          dark: true,
          km: false,
        ),
      ];
      for (final f in fixtures) {
        tester.view.physicalSize = f.size;
        tester.view.devicePixelRatio = 1;
        final prefs = AppPreferences()..locale = Locale(f.km ? 'km' : 'en');
        final key = GlobalKey();
        await tester.pumpWidget(
          AppPreferencesScope(
            preferences: prefs,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: prefs.locale,
              supportedLocales: const [Locale('en'), Locale('km')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: AppTheme.build(
                f.dark ? Brightness.dark : Brightness.light,
                locale: prefs.locale,
              ),
              home: MediaQuery(
                data: MediaQueryData(
                  size: f.size,
                  textScaler: TextScaler.linear(f.scale),
                ),
                child: RepaintBoundary(
                  key: key,
                  child: f.home
                      ? const KesorHomeScreen(
                          data: KesorHomeData.designPreview,
                          showDeviceChrome: true,
                        )
                      : ContinueWelcomePage(session),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          for (final file in [
            if (f.home) ...[
              'recipient-elon.png',
              'recipient-jeff.png',
              'recipient-warren.png',
              'transaction-elon.png',
              'transaction-jeff.png',
              'transaction-warren.png',
            ] else
              f.dark ? 'auth-night.png' : 'auth-day.png',
          ]) {
            await precacheImage(
              AssetImage('assets/${f.home ? 'home' : 'auth'}/$file'),
              key.currentContext!,
            );
          }
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: f.name);
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          final file = File('.local/qa/home-modes/${f.name}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
        });
        if (!f.home && f.scale > 1) {
          await tester.drag(
            find.byType(SingleChildScrollView),
            const Offset(0, -5000),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${f.name} scrolled footer',
          );
          await tester.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            image.dispose();
            await File('.local/qa/home-modes/${f.name}-bottom.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
        prefs.dispose();
      }
      // The actual Figma component is 320x64, with three equal 104x56 slots.
      tester.view.physicalSize = const Size(440, 560);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(Brightness.light, locale: const Locale('km')),
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 20,
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      KesorBottomBar(selectedIndex: i, onSelected: (_) {}),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('kesor-nav-capsule')).first),
        const Size(320, 64),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('bottom-tab-0')).first),
        const Size(104, 56),
      );
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await File('.local/qa/home-modes/navigation-states.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      });
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
