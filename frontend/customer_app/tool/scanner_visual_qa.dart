// This fixture is executed with flutter test and replaces the camera platform.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';
import 'dart:ui' as ui;

import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/features/accounts/accounts_controller.dart';
import 'package:customer_app/features/accounts/creation_store.dart';
import 'package:customer_app/features/qr/presentation/scan_qr_panel.dart';
import 'package:customer_app/features/transactions/transfer_controller.dart';
import 'package:customer_app/features/transactions/transfer_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../test/accounts_test.dart' show FakeAccounts;
import '../test/qr_pairs_test.dart' show FakeQr, signedSession;
import '../test/qr_widget_test.dart' show FakeCamera;
import '../test/transactions_test.dart' show FakeTransactions;

void main() {
  testWidgets('scanner full-screen layout, close, and verified handoff', (
    tester,
  ) async {
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
        for (final file in entry.value) {
          loader.addFont(rootBundle.load(file));
        }
        await loader.load();
      }
    });
    final previous = MobileScannerPlatform.instance;
    addTearDown(() {
      MobileScannerPlatform.instance = previous;
    });
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final variant in [
      (
        name: 'phone',
        size: const Size(393, 852),
        scale: 1.0,
        km: false,
        denied: false,
      ),
      (
        name: 'small',
        size: const Size(320, 640),
        scale: 1.0,
        km: false,
        denied: false,
      ),
      (
        name: 'large-text-km',
        size: const Size(375, 812),
        scale: 2.0,
        km: true,
        denied: false,
      ),
      (
        name: 'landscape',
        size: const Size(812, 375),
        scale: 1.0,
        km: false,
        denied: false,
      ),
      (
        name: 'tablet',
        size: const Size(800, 1280),
        scale: 1.3,
        km: true,
        denied: false,
      ),
      (
        name: 'permission',
        size: const Size(393, 852),
        scale: 1.0,
        km: false,
        denied: true,
      ),
    ]) {
      for (final brightness in Brightness.values) {
        MobileScannerController.resetPlatformSessionOwner();
        final camera = FakeCamera()..denied = variant.denied;
        MobileScannerPlatform.instance = camera;
        tester.view.physicalSize = variant.size;
        tester.view.devicePixelRatio = 1;
        final session = await signedSession();
        final accounts = AccountsController(
          session,
          FakeAccounts(),
          MemoryCreationStore(),
        );
        await accounts.initialize();
        final transfers = TransferController(
          session,
          FakeTransactions(),
          MemoryTransferStore(),
        );
        await transfers.initialize();
        final prefs = AppPreferences()
          ..locale = Locale(variant.km ? 'km' : 'en');
        final key = GlobalKey();
        var closed = false, handedOff = false;
        await tester.pumpWidget(
          AppPreferencesScope(
            preferences: prefs,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: prefs.locale,
              supportedLocales: const [Locale('en'), Locale('km')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: AppTheme.build(brightness, locale: prefs.locale),
              home: MediaQuery(
                data: MediaQueryData(
                  size: variant.size,
                  padding: const EdgeInsets.only(top: 24, bottom: 24),
                  textScaler: TextScaler.linear(variant.scale),
                  disableAnimations: true,
                ),
                child: RepaintBoundary(
                  key: key,
                  child: Scaffold(
                    body: ScanQrPanel(
                      session: session,
                      gateway: FakeQr(),
                      accounts: accounts,
                      transfers: transfers,
                      enabled: true,
                      onClose: () => closed = true,
                      onScanned: (preview) =>
                          handedOff = preview.destination == '1000000002',
                    ),
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
          reason: '${variant.name}-${brightness.name}',
        );
        final close = find.byKey(const ValueKey('scan-close'));
        expect(tester.getRect(close).top, greaterThanOrEqualTo(24));
        final scanner = tester.widget<MobileScanner>(
          find.byType(MobileScanner),
        );
        expect(scanner.scanWindow!.width, greaterThan(100));
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '.local/qa/scanner/${variant.name}-${brightness.name}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
        await tester.tap(close);
        expect(closed, isTrue);
        if (!variant.denied) {
          camera.captures.add(camera.imageResult);
          await tester.pumpAndSettle();
          expect(handedOff, isTrue);
          expect(camera.stops, greaterThanOrEqualTo(1));
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        accounts.dispose();
        transfers.dispose();
        session.dispose();
        prefs.dispose();
        await camera.captures.close();
        await camera.torch.close();
      }
    }
  });
}
