// Offline render fixture for Figma frame 9:43. No accounts or services are used.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:customer_app/features/home/presentation/kesor_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('render Kesor Home design and responsive variants', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final family in {
        'Google Sans': ['GoogleSans-Regular.ttf', 'GoogleSans-Medium.ttf'],
        'Poppins': ['Poppins-Regular.ttf', 'Poppins-Medium.ttf'],
        'Noto Sans Khmer': ['NotoSansKhmer-Variable.ttf'],
      }.entries) {
        final loader = FontLoader(family.key);
        for (final file in family.value) {
          loader.addFont(rootBundle.load('assets/fonts/$file'));
        }
        await loader.load();
      }
    });
    final boundary = GlobalKey();
    for (final fixture in [
      (name: 'home-440', size: const Size(440, 999), scale: 1.0),
      (name: 'home-375', size: const Size(375, 812), scale: 1.0),
      (name: 'home-large-text', size: const Size(440, 999), scale: 2.0),
      (name: 'home-landscape', size: const Size(667, 375), scale: 1.0),
    ]) {
      tester.view.physicalSize = fixture.size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: MediaQuery(
            data: MediaQueryData(
              size: fixture.size,
              textScaler: TextScaler.linear(fixture.scale),
            ),
            child: RepaintBoundary(
              key: boundary,
              child: const KesorHomeScreen(
                data: KesorHomeData.designPreview,
                showDeviceChrome: true,
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        final context = boundary.currentContext!;
        for (final image in [
          'recipient-elon.png',
          'recipient-jeff.png',
          'recipient-warren.png',
          'transaction-jeff.png',
          'transaction-elon.png',
          'transaction-warren.png',
        ]) {
          await precacheImage(AssetImage('assets/home/$image'), context);
        }
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final file = File('.local/qa/home/${fixture.name}.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
      });
      await tester.pumpWidget(const SizedBox.shrink());
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
