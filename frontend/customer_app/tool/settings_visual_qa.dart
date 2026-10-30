// Controlled demo data only. No live account reads or mutations.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/features/settings/settings_screen.dart';
import 'package:customer_app/features/settings/settings_detail_screen.dart';
import 'package:customer_app/shared/widgets/kesor_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../test/settings_test.dart' as fixture;

void main() {
  testWidgets(
    'Settings matches Figma and all feature pages adapt to small screens and Khmer',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        for (final entry in {
          'Poppins': [
            'Poppins-Regular.ttf',
            'Poppins-Medium.ttf',
            'Poppins-SemiBold.ttf',
          ],
          'Google Sans': [
            'GoogleSans-Regular.ttf',
            'GoogleSans-Medium.ttf',
            'GoogleSans-Bold.ttf',
          ],
          'Noto Sans Khmer': ['NotoSansKhmer-Variable.ttf'],
          'MaterialIcons': [],
        }.entries) {
          final font = FontLoader(entry.key);
          if (entry.key == 'MaterialIcons') {
            font.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          }
          for (final file in entry.value) {
            font.addFont(rootBundle.load('assets/fonts/$file'));
          }
          await font.load();
        }
      });
      final session = await fixture.settingsSession();
      final directory = Directory('.local/settings-visuals')
        ..createSync(recursive: true);
      for (final variant in [
        (
          name: 'reference-en',
          size: const Size(440, 999),
          scale: 1.0,
          km: false,
        ),
        (
          name: 'reference-km',
          size: const Size(440, 999),
          scale: 1.0,
          km: true,
        ),
        (name: 'small-en', size: const Size(375, 667), scale: 1.0, km: false),
        (name: 'large-km', size: const Size(320, 667), scale: 2.0, km: true),
        (
          name: 'landscape-en',
          size: const Size(812, 375),
          scale: 2.0,
          km: false,
        ),
        (name: 'tablet-en', size: const Size(800, 1280), scale: 1.3, km: false),
      ]) {
        for (final dark in [false, true]) {
          final prefs = AppPreferences()
            ..locale = Locale(variant.km ? 'km' : 'en');
          final pages =
              variant.name == 'reference-en' || variant.name == 'large-km'
              ? [
                  'root',
                  'profile',
                  'pin',
                  'notifications',
                  'language',
                  'appearance',
                  'help',
                  'legal',
                  'signout',
                ]
              : ['root'];
          for (final page in pages) {
            tester.view.physicalSize = variant.size;
            tester.view.devicePixelRatio = 1;
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
                    dark ? Brightness.dark : Brightness.light,
                    locale: prefs.locale,
                  ),
                  home: MediaQuery(
                    data: MediaQueryData(
                      size: variant.size,
                      textScaler: TextScaler.linear(variant.scale),
                      padding: EdgeInsets.only(
                        top: variant.name.startsWith('reference') ? 54 : 24,
                      ),
                      disableAnimations: true,
                    ),
                    child: RepaintBoundary(
                      key: key,
                      child: page == 'root'
                          ? Scaffold(
                              body: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 440,
                                  ),
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: SettingsScreen(
                                          session: session,
                                          onOpen: (_) {},
                                        ),
                                      ),
                                      Positioned(
                                        left: 20,
                                        right: 20,
                                        bottom: 24,
                                        child: KesorBottomBar(
                                          selectedIndex: 2,
                                          onSelected: (_) {},
                                          onAssistant: () {},
                                        ),
                                      ),
                                      if (variant.name.startsWith(
                                        'reference',
                                      )) ...[
                                        Positioned(
                                          top: 0,
                                          left: 36,
                                          right: 30,
                                          height: 54,
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                '9:41',
                                                style: TextStyle(
                                                  fontFamily: 'Google Sans',
                                                  fontSize: 17,
                                                  height: 22 / 17,
                                                  color: dark
                                                      ? Colors.white
                                                      : Colors.black,
                                                ),
                                              ),
                                              SvgPicture.asset(
                                                'assets/settings/device-status.svg',
                                                width: 75,
                                                height: 16,
                                                colorFilter: dark
                                                    ? const ColorFilter.mode(
                                                        Colors.white,
                                                        BlendMode.srcIn,
                                                      )
                                                    : null,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Positioned(
                                          bottom: 5,
                                          left: 153,
                                          width: 134,
                                          height: 5,
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: dark
                                                  ? Colors.white
                                                  : Colors.black,
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : SettingsDetailScreen(
                              key: ValueKey('$page-${variant.name}-$dark'),
                              page: page,
                              session: session,
                              onBack: () {},
                              onAssistant: () {},
                              platform: fixture.FakeSettingsPlatform(),
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
              reason: '$page ${variant.name} dark=$dark',
            );
            if (page == 'root' && variant.name == 'reference-en') {
              expect(
                tester.getTopLeft(
                  find.byKey(const ValueKey('settings-profile')),
                ),
                const Offset(20, 148),
              );
              expect(
                tester
                    .getRect(find.byKey(const ValueKey('settings-signout')))
                    .top,
                822,
              );
            }
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final bitmap = await boundary.toImage(pixelRatio: 1);
              final bytes = await bitmap.toByteData(
                format: ui.ImageByteFormat.png,
              );
              File(
                '${directory.path}/$page-${variant.name}-${dark ? 'dark' : 'light'}.png',
              ).writeAsBytesSync(bytes!.buffer.asUint8List());
              bitmap.dispose();
            });
            if (page == 'root') {
              await tester.ensureVisible(
                find.byKey(const ValueKey('settings-signout')),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }
          }
          await tester.pumpWidget(const SizedBox.shrink());
          prefs.dispose();
        }
      }
      session.dispose();
    },
  );
}
