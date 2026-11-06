import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_app/core/merchant_preferences.dart';
import 'package:merchant_app/features/auth/merchant_session.dart';

import '../test/merchant_auth_diagnostics_test.dart'
    show DiagnosticAuth, diagnosticApp;

void main() {
  testWidgets(
    'Merchant sign-in errors adapt across language, theme and text size',
    (tester) async {
      await tester.runAsync(() async {
        for (final entry in {
          'MaterialIcons': ['fonts/MaterialIcons-Regular.otf'],
          'Poppins': [
            'assets/fonts/Poppins-Regular.ttf',
            'assets/fonts/Poppins-Medium.ttf',
            'assets/fonts/Poppins-SemiBold.ttf',
          ],
          'Google Sans': [
            'assets/fonts/GoogleSans-Regular.ttf',
            'assets/fonts/GoogleSans-Medium.ttf',
            'assets/fonts/GoogleSans-Bold.ttf',
          ],
          'Noto Sans Khmer': ['assets/fonts/NotoSansKhmer-Variable.ttf'],
        }.entries) {
          final loader = FontLoader(entry.key);
          for (final path in entry.value) {
            loader.addFont(rootBundle.load(path));
          }
          await loader.load();
        }
      });
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      var count = 0;
      for (final issue in [
        MerchantAuthIssue.appMismatch,
        MerchantAuthIssue.unsupportedBuild,
        MerchantAuthIssue.openFailed,
        MerchantAuthIssue.storageUnavailable,
        MerchantAuthIssue.serverUnavailable,
        MerchantAuthIssue.rejected,
        MerchantAuthIssue.invalidResponse,
        MerchantAuthIssue.uncertain,
      ]) {
        for (final size in [
          const Size(393, 852),
          const Size(320, 568),
          const Size(800, 1280),
        ]) {
          for (final dark in [false, true]) {
            for (final km in [false, true]) {
              for (final scale in [1.0, 2.0]) {
                tester.view.physicalSize = size;
                tester.platformDispatcher.textScaleFactorTestValue = scale;
                final prefs = MerchantPreferences()
                  ..setLanguage(km ? 'km' : 'en')
                  ..setTheme(dark ? ThemeMode.dark : ThemeMode.light);
                final session = MerchantSession(
                  DiagnosticAuth(
                    MerchantAuthFailure(
                      issue,
                      diagnostic: const MerchantAuthDiagnostic(
                        MerchantAuthStage.verifyCustomer,
                        'PEER_SIGNATURE_MISMATCH',
                      ),
                    ),
                  ),
                );
                await session.signIn();
                final boundary = GlobalKey();
                await tester.pumpWidget(
                  RepaintBoundary(
                    key: boundary,
                    child: diagnosticApp(session, prefs),
                  ),
                );
                await tester.pumpAndSettle();
                final name =
                    '${issue.name}-${size.width.toInt()}-${dark ? 'dark' : 'light'}-${km ? 'km' : 'en'}-$scale';
                final copy = find.byKey(
                  const ValueKey('copy-merchant-auth-details'),
                );
                await tester.ensureVisible(copy);
                await tester.pumpAndSettle();
                expect(
                  tester.getSize(copy).height,
                  greaterThanOrEqualTo(48),
                  reason: name,
                );
                for (final action in [
                  find.byType(FilledButton),
                  find.byType(OutlinedButton),
                ]) {
                  if (action.evaluate().isNotEmpty) {
                    await tester.ensureVisible(action);
                    await tester.pumpAndSettle();
                    expect(
                      tester.getSize(action).height,
                      greaterThanOrEqualTo(48),
                      reason: name,
                    );
                  }
                }
                final scroll = tester.state<ScrollableState>(
                  find.byType(Scrollable).first,
                );
                scroll.position.jumpTo(0);
                await tester.pumpAndSettle();
                expect(tester.takeException(), null, reason: name);
                await tester.runAsync(() async {
                  final render =
                      boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary;
                  final image = await render.toImage(pixelRatio: 1);
                  final bytes = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  final dir = Directory('.local/qa/merchant-auth')
                    ..createSync(recursive: true);
                  File('${dir.path}/$name.png')
                      .writeAsBytesSync(bytes!.buffer.asUint8List());
                  image.dispose();
                });
                await tester.pumpWidget(const SizedBox());
                session.dispose();
                prefs.dispose();
                count++;
              }
            }
          }
        }
      }
      // ignore: avoid_print
      print(
        'Merchant auth: $count responsive renders; no layout exceptions; copy targets >=48dp.',
      );
    },
  );
}
