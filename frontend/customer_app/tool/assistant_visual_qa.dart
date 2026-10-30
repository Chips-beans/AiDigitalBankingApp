import 'dart:io';
import 'dart:ui' as ui;

import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/banking_app.dart';
import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/features/accounts/creation_store.dart';
import 'package:customer_app/features/assistant/assistant_store.dart';
import 'package:customer_app/features/transactions/transfer_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/accounts_test.dart' show FakeAccounts;
import '../test/qr_pairs_test.dart' show signedSession;
import '../test/transactions_test.dart' show FakeTransactions, funded;
import '../test/support/assistant_fakes.dart';

void main() {
  testWidgets('render core assistant in English/Khmer and both themes', (
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
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    for (final variant in [
      (name: 'reference-en', size: const Size(440, 956), scale: 1.0, km: false),
      (name: 'reference-km', size: const Size(440, 956), scale: 1.0, km: true),
      (name: 'small-en', size: const Size(375, 667), scale: 1.0, km: false),
      (name: 'large-text-km', size: const Size(320, 667), scale: 2.0, km: true),
      (name: 'landscape-en', size: const Size(812, 375), scale: 2.0, km: false),
      (name: 'tablet-en', size: const Size(1024, 768), scale: 1.0, km: false),
    ]) {
      tester.view.physicalSize = variant.size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = variant.scale;
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final session = await signedSession(), api = FakeAssistant();
        final prefs = AppPreferences()
          ..locale = Locale(variant.km ? 'km' : 'en')
          ..themeMode = brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light;
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: BankingApp(
              session: session,
              config: AppConfig(
                apiBaseUrl: 'http://localhost:8080/api/v1',
                environment: 'dev',
              ),
              preferences: prefs,
              accountGateway: FakeAccounts()
                ..data = [
                  funded(1, balance: '190.00'),
                  funded(2, currency: 'KHR', balance: '90000'),
                ],
              creationStore: MemoryCreationStore(),
              transactionGateway: FakeTransactions(),
              transferStore: MemoryTransferStore(),
              assistantGateway: api,
              assistantStore: AssistantPendingStore(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('AI assistant'));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          null,
          reason: '${variant.name} $brightness welcome',
        );
        Future<void> capture(String state) async {
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1),
                bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
              '.local/qa/assistant/${variant.name}-${brightness.name}-$state.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('welcome');
        await tester.enterText(
          find.byKey(const ValueKey('assistant-question')),
          variant.km ? 'សូមបង្ហាញសមតុល្យរបស់ខ្ញុំ' : 'Show my balances',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('assistant-send')));
        await tester.pumpAndSettle();
        expect(api.requests, hasLength(1));
        expect(
          tester.takeException(),
          null,
          reason: '${variant.name} $brightness answer',
        );
        await capture('answer');
        await tester.pumpWidget(const SizedBox.shrink());
        session.dispose();
        prefs.dispose();
      }
    }
  });
}
