// Optional local screenshot capture: flutter test tool/visual_qa.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:customer_app/app/banking_app.dart';
import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/auth/data/auth_gateway.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:customer_app/features/accounts/account_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('capture authentication screens for visual review', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final flutterRoot = Platform.environment['FLUTTER_ROOT'];
      if (flutterRoot == null) {
        throw StateError(
          'Set FLUTTER_ROOT to load the SDK Roboto fonts for visual review',
        );
      }
      final fonts = FontLoader('Roboto');
      fonts.addFont(
        File(
          '$flutterRoot/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
        ).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
      );
      await fonts.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(
        File(
          '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
        ).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
      );
      await icons.load();
    });
    final session = SessionController(DemoAuthGateway(), MemorySessionVault());
    final accounts = DemoAccountGateway();
    await accounts.open('demo', 'SAVINGS', 'USD');
    await accounts.open('demo', 'CHECKING', 'KHR');
    final config = AppConfig(
      apiBaseUrl: 'http://localhost:8080/api/v1',
      environment: 'dev',
      mode: 'demo',
    );
    final boundary = GlobalKey();
    await session.initialize();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: BankingApp(
          session: session,
          config: config,
          accountGateway: accounts,
        ),
      ),
    );
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final file = File('.local/qa/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
      });
    }

    await capture('welcome');
    session.openForm(register: true);
    await capture('register');
    await session.begin(
      email: 'customer@example.test',
      password: 'Password123!',
      username: 'customer',
      register: true,
    );
    await capture('otp');
    await session.verifyCode('123456');
    await capture('f3-home');
    await tester.tap(find.byTooltip('Activity'));
    await capture('f3-activity');
    await tester.tap(find.text('Profile'));
    await capture('profile');
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('View accounts'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Open account'));
    await tester.tap(find.text('Open account'));
    await capture('f3-open-account');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    session.dispose();
  });
}
