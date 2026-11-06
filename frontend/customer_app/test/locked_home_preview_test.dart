import 'package:flutter/services.dart';
import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/app_theme.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/auth/data/app_pin_gateway.dart';
import 'package:customer_app/features/auth/data/auth_gateway.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:customer_app/features/home/home_preview_gateway.dart';
import 'package:customer_app/features/home/home_unlock_target.dart';
import 'package:customer_app/features/home/presentation/locked_home_page.dart';
import 'package:customer_app/features/transactions/recipient_favorites.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Preview implements HomePreviewGateway {
  @override
  Future<List<HomePreviewEntry>> load(String ticket) async => [
    HomePreviewEntry(
      'receipt-1',
      'Preview Sender',
      DateTime.utc(2026, 11, 6),
      'INCOMING',
      'SUCCESS',
    ),
  ];
}

void main() {
  testWidgets(
    'locked preview shows saved people and activity, and gates selection',
    (tester) async {
      tester.view.physicalSize = const Size(480, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        for (final family in {
          'Poppins': 'Poppins-Regular.ttf',
          'Google Sans': 'GoogleSans-Regular.ttf',
          'Noto Sans Khmer': 'NotoSansKhmer-Variable.ttf',
        }.entries) {
          final loader = FontLoader(family.key)
            ..addFont(rootBundle.load('assets/fonts/${family.value}'));
          await loader.load();
        }
      });
      await tester.runAsync(() async {
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      });
      final session = SessionController(
        DemoAuthGateway(),
        MemorySessionVault(),
      );
      addTearDown(session.dispose);
      session.phase = SessionPhase.pinLocked;
      session.pinStage = PinStage.unlock;
      session.pinChallenge = const PinChallenge(
        ticket: 'preview-ticket',
        userId: 7,
        configured: true,
        attemptsRemaining: 5,
        recoveryRequired: false,
        canRecover: false,
        displayName: 'Owner',
      );
      final favorites = RecipientFavoritesStore();
      await favorites.add(
        7,
        const FavoriteRecipient(
          '123456789012',
          'USD',
          name: 'Saved Dara',
          manual: true,
        ),
      );
      await favorites.add(
        8,
        const FavoriteRecipient(
          '123456789013',
          'USD',
          name: 'Other Owner',
          manual: true,
        ),
      );
      HomeUnlockTarget? target;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: RepaintBoundary(
            key: const ValueKey('preview-capture'),
            child: LockedHomePage(
              session: session,
              favorites: favorites,
              previewGateway: Preview(),
              onUnlock: (value) => target = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Saved Dara'), findsOneWidget);
      expect(find.text('Other Owner'), findsNothing);
      expect(find.text('Preview Sender'), findsOneWidget);
      expect(find.textContaining('••••'), findsWidgets);
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('preview-capture')),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final folder = Directory('.local/qa/pin-preview')
          ..createSync(recursive: true);
        await File('${folder.path}/home-preview.png')
            .writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      });
      await tester.tap(find.text('Saved Dara'));
      expect(target?.page, 'transfer');
      expect(target?.recipient, '123456789012');
      await tester.tap(find.text('Preview Sender'));
      expect(target?.reference, 'receipt-1');
      expect(target?.page, 'transaction');
      for (final size in [
        const Size(375, 812),
        const Size(667, 375),
        const Size(800, 1280),
      ]) {
        for (final language in ['en', 'km']) {
          for (final mode in [Brightness.light, Brightness.dark]) {
            tester.view.physicalSize = size;
            final prefs = AppPreferences()..locale = Locale(language);
            await tester.pumpWidget(
              AppPreferencesScope(
                preferences: prefs,
                child: MaterialApp(
                  theme: AppTheme.build(mode, locale: Locale(language)),
                  home: RepaintBoundary(
                    key: const ValueKey('preview-capture'),
                    child: LockedHomePage(
                      session: session,
                      favorites: favorites,
                      previewGateway: Preview(),
                      onUnlock: (_) {},
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.runAsync(() async {
              final image = await tester
                  .renderObject<RenderRepaintBoundary>(
                    find.byKey(const ValueKey('preview-capture')),
                  )
                  .toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '.local/qa/pin-preview/${size.width.toInt()}-${size.height.toInt()}-$language-${mode.name}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
            await tester.pumpWidget(const SizedBox.shrink());
            prefs.dispose();
          }
        }
      }
    },
  );
  test('preview parser refuses malformed directions and dates', () {
    expect(
      () => HomePreviewEntry.parse({
        'reference': 'r',
        'name': 'N',
        'createdAt': 'bad',
        'direction': 'UNKNOWN',
        'status': 'SUCCESS',
      }),
      throwsFormatException,
    );
  });
}
