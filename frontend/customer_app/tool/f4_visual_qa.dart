// Render-only fixture screenshots. No backend requests, emails or real transfers.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:customer_app/app/banking_app.dart';
import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/accounts/creation_store.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:customer_app/features/transactions/transfer_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/accounts_test.dart' show FakeAccounts;
import '../test/support/fakes.dart';
import '../test/transactions_test.dart' show FakeTransactions, funded;

void main() {
  testWidgets('render F4 fixture screens', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final root = Platform.environment['FLUTTER_ROOT']!;
      for (final font in [
        ('Roboto', 'roboto-regular.ttf'),
        ('MaterialIcons', 'materialicons-regular.otf'),
      ]) {
        final loader = FontLoader(font.$1)
          ..addFont(
            File('$root/bin/cache/artifacts/material_fonts/${font.$2}')
                .readAsBytes()
                .then((b) => b.buffer.asByteData()),
          );
        await loader.load();
      }
    });
    final session = SessionController(
      FakeGateway()..expiresInMs = 600000,
      MemorySessionVault(),
    );
    await session.initialize();
    await session.begin(
      email: 'fixture@example.test',
      password: 'FixtureOnly!',
      register: false,
    );
    await session.verifyCode('123456');
    final transactions = FakeTransactions();
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
          accountGateway: FakeAccounts()..data = [funded(1)],
          creationStore: MemoryCreationStore(),
          transactionGateway: transactions,
          transferStore: MemoryTransferStore(),
        ),
      ),
    );
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final rendered =
            await (key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
        rendered.dispose();
        final file = File('.local/qa/f4/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
      });
    }

    Future<void> tap(String label) async {
      final finder = find.text(label).evaluate().isNotEmpty
          ? find.text(label).first
          : find.byTooltip(label).first;
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await tester.pumpAndSettle();
    await tap('Transfer');
    await capture('entry');
    await tester.enterText(
      find.byKey(const ValueKey('transfer-destination')),
      funded(2).number,
    );
    await tester.enterText(
      find.byKey(const ValueKey('transfer-amount')),
      '5.00',
    );
    await tester.enterText(
      find.byKey(const ValueKey('transfer-remark')),
      'Fixture transfer',
    );
    await tap('Review transfer');
    await capture('review');
    await tap('Confirm and send');
    await capture('confirmed');
    transactions.historyItems = transactions.committed.values.toList();
    await tap('Activity');
    await tap('Refresh recent activity');
    await capture('history');
    await tap('View transaction details');
    await capture('detail');
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await capture('detail-dark');
    tester.platformDispatcher.clearAllTestValues();
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });
}
