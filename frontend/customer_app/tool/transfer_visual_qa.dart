import 'dart:io';
import 'dart:ui' as ui;

import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/features/accounts/accounts_controller.dart';
import 'package:customer_app/features/accounts/creation_store.dart';
import 'package:customer_app/features/transactions/recipient_favorites.dart';
import 'package:customer_app/features/transactions/presentation/kesor_transfer_screen.dart';
import 'package:customer_app/features/transactions/transfer_controller.dart';
import 'package:customer_app/features/transactions/transfer_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/accounts_test.dart' show FakeAccounts;
import '../test/qr_pairs_test.dart' show signedSession;
import '../test/transactions_test.dart' show funded, FakeTransactions;

void main() {
  testWidgets('render Figma 273:356 and adaptive English/Khmer transfer views', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final entry in {
        'MaterialIcons': ['fonts/MaterialIcons-Regular.otf'],
        'Poppins': [
          'assets/fonts/Poppins-Regular.ttf',
          'assets/fonts/Poppins-Medium.ttf',
          'assets/fonts/Poppins-Bold.ttf',
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
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final variant in [
      (name: 'reference-en', size: const Size(440, 956), scale: 1.0, km: false),
      (name: 'reference-km', size: const Size(440, 956), scale: 1.0, km: true),
      (
        name: 'reference-khr',
        size: const Size(440, 956),
        scale: 1.0,
        km: false,
      ),
      (name: 'small-en', size: const Size(375, 667), scale: 1.0, km: false),
      (name: 'large-text-km', size: const Size(320, 667), scale: 2.0, km: true),
      (name: 'landscape-en', size: const Size(812, 375), scale: 2.0, km: false),
      (name: 'tablet-en', size: const Size(1024, 768), scale: 1.0, km: false),
    ]) {
      tester.view.physicalSize = variant.size;
      tester.view.devicePixelRatio = 1;
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final session = await signedSession();
        final accounts = AccountsController(
          session,
          FakeAccounts()
            ..data = [
              funded(1, balance: '168.00'),
              funded(3, currency: 'KHR', balance: '100000'),
            ],
          MemoryCreationStore(),
        );
        await accounts.initialize();
        if (variant.name == 'reference-khr') {
          await accounts.select(accounts.accounts.last);
        }
        final transfers = TransferController(
          session,
          FakeTransactions(),
          MemoryTransferStore(),
        );
        await transfers.initialize();
        final prefs = AppPreferences()
          ..locale = Locale(variant.km ? 'km' : 'en');
        final key = GlobalKey();
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
                  disableAnimations: true,
                ),
                child: RepaintBoundary(
                  key: key,
                  child: KesorTransferScreen(
                    controller: transfers,
                    accounts: accounts,
                    enabled: true,
                    onBack: () {},
                    favorites: RecipientFavoritesStore(),
                    showDeviceChrome: true,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/transfer/flag-us.png'),
            key.currentContext!,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          null,
          reason: '${variant.name}-${brightness.name}',
        );
        if (variant.name == 'reference-en') {
          for (final entry in {
            'transfer-emblem': const Offset(184, 138),
            'transfer-form-panel': const Offset(0, 288),
            'transfer-wallet-picker': const Offset(24, 338),
            'transfer-receiver-frame': const Offset(24, 436.75),
            'transfer-amount-frame': const Offset(24, 557.5),
            'transfer-remark-frame': const Offset(24, 678.25),
            'transfer-continue': const Offset(24, 866),
          }.entries) {
            final position = tester.getTopLeft(find.byKey(ValueKey(entry.key)));
            expect(position.dx, closeTo(entry.value.dx, 1), reason: entry.key);
            expect(position.dy, closeTo(entry.value.dy, 1), reason: entry.key);
          }
          expect(
            tester.getSize(find.byKey(const ValueKey('transfer-continue'))),
            const Size(392, 54),
          );
        }
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '.local/qa/transfer/${variant.name}-${brightness.name}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
        await tester.ensureVisible(
          find.byKey(const ValueKey('transfer-continue')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), null);
        if (variant.scale > 1) {
          expect(
            tester
                .getSize(find.byKey(const ValueKey('transfer-continue')))
                .height,
            greaterThan(54),
          );
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '.local/qa/transfer/${variant.name}-${brightness.name}-footer.png',
            ).writeAsBytes(png!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
        transfers.dispose();
        accounts.dispose();
        session.dispose();
        prefs.dispose();
      }
    }
  });
}
