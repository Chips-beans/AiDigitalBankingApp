import 'dart:io';
import 'dart:ui' as ui;

import 'package:customer_app/app/app_labels.dart';
import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/features/accounts/accounts_controller.dart';
import 'package:customer_app/features/accounts/creation_store.dart';
import 'package:customer_app/features/accounts/pair_opening.dart';
import 'package:customer_app/features/accounts/presentation/pair_opening_panel.dart';
import 'package:customer_app/features/qr/presentation/receive_qr_panel.dart';
import 'package:customer_app/features/qr/presentation/scan_qr_panel.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../test/qr_widget_test.dart' show FakeCamera;

import 'package:customer_app/features/transactions/transfer_controller.dart';
import 'package:customer_app/features/transactions/transfer_store.dart';
import 'package:customer_app/features/transactions/presentation/transfer_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/accounts_test.dart' show FakeAccounts;
import '../test/qr_pairs_test.dart'
    show FakePairs, FakeQr, signedSession, sampleQr;
import '../test/transactions_test.dart' show funded, FakeTransactions;

void main() {
  testWidgets(
    'render paired opening, receive QR, review and receipt across themes and languages',
    (tester) async {
      final previousCamera = MobileScannerPlatform.instance;
      MobileScannerPlatform.instance = FakeCamera();
      addTearDown(() {
        MobileScannerPlatform.instance = previousCamera;
      });
      await tester.runAsync(() async {
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
        for (final entry in {
          'Google Sans': [
            'GoogleSans-Regular.ttf',
            'GoogleSans-Medium.ttf',
            'GoogleSans-Bold.ttf',
          ],
          'Poppins': [
            'Poppins-Regular.ttf',
            'Poppins-Medium.ttf',
            'Poppins-SemiBold.ttf',
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
        (name: 'narrow', size: const Size(320, 640), scale: 1.0, km: false),
        (
          name: 'large-text-km',
          size: const Size(375, 812),
          scale: 2.0,
          km: true,
        ),
        (name: 'landscape', size: const Size(812, 375), scale: 1.0, km: false),
      ]) {
        tester.view.physicalSize = variant.size;
        tester.view.devicePixelRatio = 1;
        for (final brightness in [Brightness.light, Brightness.dark]) {
          final session = await signedSession();
          final accounts = AccountsController(
            session,
            FakeAccounts()
              ..data = [
                funded(1, balance: '200'),
                funded(3, currency: 'KHR', balance: '100000'),
              ],
            MemoryCreationStore(),
          );
          await accounts.initialize();
          final pairs = PairOpeningController(
            session,
            FakePairs(),
            PairOpeningStore(),
            onSuccess: () async {},
          );
          final transfers = TransferController(
            session,
            FakeTransactions(),
            MemoryTransferStore(),
          );
          await transfers.initialize();
          final prefs = AppPreferences()
            ..locale = Locale(variant.km ? 'km' : 'en');
          for (final mode in [
            'opening',
            'receive',
            'fixed',
            'scanner-fixture',
            'review',
            'receipt',
          ]) {
            if (mode == 'review') {
              transfers.prepare(
                funded(1, balance: '200'),
                '1000000002',
                '10',
                '',
                qrString: sampleQr,
                destinationName: 'Sok Dara',
              );
            }
            if (mode == 'receipt') await transfers.confirm();
            final key = GlobalKey();
            final title = mode == 'opening'
                ? 'Open accounts'
                : (mode == 'receive' || mode == 'fixed')
                ? 'My QR'
                : 'Scan QR';
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
                      textScaler: TextScaler.linear(variant.scale),
                    ),
                    child: RepaintBoundary(
                      key: key,
                      child: Builder(
                        builder: (context) => Scaffold(
                          appBar: AppBar(title: Text(tx(context, title))),
                          body: SafeArea(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(20),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 400,
                                  ),
                                  child: mode == 'opening'
                                      ? PairOpeningPanel(
                                          model: pairs,
                                          legacyPending: false,
                                          onOpened: () {},
                                        )
                                      : (mode == 'receive' || mode == 'fixed')
                                      ? ReceiveQrPanel(
                                          session: session,
                                          gateway: FakeQr(),
                                          accounts: accounts,
                                        )
                                      : mode == 'scanner-fixture'
                                      ? ScanQrPanel(
                                          session: session,
                                          gateway: FakeQr(),
                                          accounts: accounts,
                                          transfers: transfers,
                                          enabled: true,
                                        )
                                      : TransferPanel(
                                          controller: transfers,
                                          accounts: accounts,
                                          enabled: true,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            if (mode == 'fixed') {
              await tester.ensureVisible(find.byType(SwitchListTile));
              await tester.tap(find.byType(SwitchListTile));
              await tester.pumpAndSettle();
              await tester.enterText(
                find.byKey(const ValueKey('qr-request-amount')),
                '10',
              );
              final button = find.byType(FilledButton);
              await tester.ensureVisible(button);
              await tester.tap(button);
              await tester.pumpAndSettle();
              await tester.drag(
                find.byType(SingleChildScrollView).first,
                const Offset(0, 2000),
              );
              await tester.pumpAndSettle();
            }
            expect(
              tester.takeException(),
              null,
              reason: '$mode-${variant.name}-${brightness.name}',
            );
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 1);
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                '.local/qa/qr/$mode-${variant.name}-${brightness.name}.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(png!.buffer.asUint8List());
              image.dispose();
            });
            await tester.pumpWidget(const SizedBox.shrink());
          }
          pairs.dispose();
          transfers.dispose();
          accounts.dispose();
          session.dispose();
          prefs.dispose();
        }
      }
    },
  );
}
