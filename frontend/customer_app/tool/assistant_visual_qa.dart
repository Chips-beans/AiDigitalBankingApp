import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/features/assistant/assistant_controller.dart';
import 'package:customer_app/features/assistant/assistant_store.dart';
import 'package:customer_app/features/assistant/presentation/assistant_screen.dart';

import '../test/qr_pairs_test.dart' show signedSession;
import '../test/support/assistant_fakes.dart';
import '../test/wallet_details_design_test.dart' show detailsHarness;

void main() {
  testWidgets('assistant reference and responsive matrix', (tester) async {
    await tester.runAsync(() async {
      for (final family in {
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
        final loader = FontLoader(family.key);
        for (final file in family.value) {
          loader.addFont(rootBundle.load('assets/fonts/$file'));
        }
        await loader.load();
      }
      for (final asset in [
        'assets/assistant/68b0e.svg',
        'assets/assistant/0e542.svg',
        'assets/figma/03138.svg',
        'assets/figma/6fd29.svg',
      ]) {
        await SvgAssetLoader(asset).loadBytes(null);
      }
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var count = 0;
    for (final size in [
      const Size(440, 999),
      const Size(320, 568),
      const Size(375, 812),
      const Size(667, 375),
      const Size(844, 390),
      const Size(800, 1280),
    ]) {
      for (final dark in [false, true]) {
        for (final km in [false, true]) {
          for (final scale in [1.0, 1.3, 2.0]) {
            final session = await signedSession();
            final model = AssistantController(
              session,
              FakeAssistant(),
              AssistantPendingStore(),
            );
            final prefs = AppPreferences()..locale = Locale(km ? 'km' : 'en');
            final boundary = GlobalKey();
            tester.view.physicalSize = size;
            final reference = size == const Size(440, 999);
            await tester.pumpWidget(
              detailsHarness(
                RepaintBoundary(
                  key: boundary,
                  child: Scaffold(
                    body: AssistantScreen(
                      controller: model,
                      onAction: (_) {},
                      onBack: () {},
                      bottomClearance: 0,
                    ),
                  ),
                ),
                preferences: prefs,
                size: size,
                dark: dark,
                scale: scale,
                padding: EdgeInsets.only(
                  top: reference ? 54 : 24,
                  bottom: reference ? 0 : 24,
                ),
              ),
            );
            await tester.pumpAndSettle();
            final label =
                '${size.width.toInt()}x${size.height.toInt()}-${dark ? 'dark' : 'light'}-${km ? 'km' : 'en'}-$scale';
            expect(tester.takeException(), isNull, reason: label);
            expect(
              find.byKey(const ValueKey('assistant-suggestion-3')),
              findsNothing,
            );
            for (var i = 0; i < 3; i++) {
              await tester.ensureVisible(
                find.byKey(ValueKey('assistant-suggestion-$i')),
              );
              await tester.pumpAndSettle();
              expect(
                tester
                    .getSize(find.byKey(ValueKey('assistant-suggestion-$i')))
                    .height,
                greaterThanOrEqualTo(48),
              );
            }
            if (reference && !dark && !km && scale == 1) {
              expect(
                tester
                    .getTopLeft(find.byKey(const ValueKey('assistant-emblem')))
                    .dy,
                154,
              );
              expect(
                tester
                    .getTopLeft(
                      find.byKey(const ValueKey('assistant-suggestions')),
                    )
                    .dy,
                821,
              );
              expect(
                tester
                    .getTopLeft(
                      find.byKey(const ValueKey('assistant-question')),
                    )
                    .dy,
                887,
              );
            }
            // Reset both scroll directions for the reference composition.
            for (final state in tester.stateList<ScrollableState>(
              find.byType(Scrollable),
            )) {
              state.position.jumpTo(0);
            }
            await tester.pump();
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 1);
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final dir = Directory('.local/qa/assistant-redesign')
                ..createSync(recursive: true);
              File('${dir.path}/$label.png')
                  .writeAsBytesSync(png!.buffer.asUint8List());
              image.dispose();
            });
            await tester.pumpWidget(const SizedBox());
            model.dispose();
            session.dispose();
            prefs.dispose();
            count++;
          }
        }
      }
    }
    // ignore: avoid_print
    print('Assistant: $count renders; all suggestions reachable; no overflow.');
  });
}
