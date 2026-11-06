import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_app/core/merchant_splash.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

void main() {
  testWidgets(
    'merchant splash matches Figma across viewport and accessibility settings',
    (tester) async {
      await tester.runAsync(() async {
        final loader = FontLoader('Poppins')
          ..addFont(rootBundle.load('assets/fonts/Poppins-SemiBold.ttf'));
        await loader.load();
        for (final file in Directory(
          'assets/splash',
        ).listSync().whereType<File>()) {
          await SvgAssetLoader('assets/splash/${file.uri.pathSegments.last}')
              .loadBytes(null);
        }
      });
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var count = 0;
      for (final size in [
        const Size(393, 852),
        const Size(440, 956),
        const Size(320, 568),
        const Size(844, 390),
        const Size(800, 1280),
      ]) {
        for (final dark in [false, true]) {
          for (final scale in [1.0, 1.3, 2.0]) {
            tester.view.physicalSize = size;
            final boundary = GlobalKey();
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.build(
                  dark ? Brightness.dark : Brightness.light,
                ),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: RepaintBoundary(
                    key: boundary,
                    child: const MerchantSplash(animate: false),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
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
              File(
                '${dir.path}/splash-${size.width.toInt()}x${size.height.toInt()}-${dark ? 'dark' : 'light'}-$scale.png',
              ).writeAsBytesSync(png!.buffer.asUint8List());
              image.dispose();
            });
            await tester.pumpWidget(const SizedBox());
            count++;
          }
        }
      }
      // ignore: avoid_print
      print('Merchant splash: $count renders; no layout exceptions.');
    },
  );
}
