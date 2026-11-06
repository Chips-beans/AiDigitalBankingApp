import 'dart:io';
import 'dart:ui' as ui;

import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/features/analytics/analytics_controller.dart';
import 'package:customer_app/features/analytics/analytics_gateway.dart';
import 'package:customer_app/features/analytics/presentation/analytics_screen.dart';
import 'package:customer_app/shared/widgets/kesor_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/analytics_test.dart' show analyticsSession, loadAnalyticsFonts;

void main() {
  testWidgets('render analytics source geometry and responsive modes', (
    tester,
  ) async {
    await loadAnalyticsFonts(tester);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = await analyticsSession();
    addTearDown(session.dispose);
    for (final dark in [false, true]) {
      for (final km in [false, true]) {
        for (final narrow in [false, true]) {
          final size = narrow ? const Size(320, 568) : const Size(440, 956);
          final locale = Locale(km ? 'km' : 'en');
          final preferences = AppPreferences()..locale = locale;
          final model = AnalyticsController(
            session,
            DemoAnalyticsGateway(),
            clock: () => DateTime.utc(2025, 10),
          );
          await model.refresh();
          final key = GlobalKey();
          tester.view.physicalSize = size;
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: locale,
              supportedLocales: const [Locale('en'), Locale('km')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: AppTheme.build(
                dark ? Brightness.dark : Brightness.light,
                locale: locale,
              ),
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(narrow ? 2 : 1),
                ),
                child: AppPreferencesScope(
                  preferences: preferences,
                  child: RepaintBoundary(
                    key: key,
                    child: Scaffold(
                      body: Stack(
                        children: [
                          Positioned.fill(
                            child: AnalyticsScreen(
                              controller: model,
                              showDeviceChrome: true,
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
              key.currentContext!,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final stem =
              'analytics-${dark ? 'dark' : 'light'}-${km ? 'km' : 'en'}${narrow ? '-small' : ''}';
          Future<void> save(String name) => tester.runAsync(() async {
            final picture =
                await (key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            picture.dispose();
            final file = File('.local/qa/analytics/$name.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
          });
          await save(stem);
          if (narrow) {
            expect(find.byType(Scrollable), findsNothing);
            expect(tester.takeException(), isNull);
            await save('$stem-bottom');
          } else {
            // Income series in gold, on a past month with Next available.
            await model.selectMonth(-1);
            model.selectSeries(true);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await save('$stem-income-previous-month');
          }
          await tester.pumpWidget(const SizedBox.shrink());
          model.dispose();
          preferences.dispose();
        }
      }
    }
  });
}
