// Synthetic owner-transfer approval records only. No live identity, PIN or API calls.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/features/merchant/merchant_transfer_approval_screen.dart';

import '../test/settings_test.dart' show settingsSession;
import '../test/merchant_transfer_test.dart'
    show TransferRig, intentId, handoff;

void main() {
  testWidgets(
    'M8 transfer approval adapts across themes, languages, currencies and large text',
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
          final font = FontLoader(entry.key);
          for (final path in entry.value) {
            font.addFont(rootBundle.load(path));
          }
          await font.load();
        }
      });
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      final directory = Directory('.local/qa/merchant-m8')
        ..createSync(recursive: true);
      final rig = TransferRig(await settingsSession());
      rig.model.pending = {
        'id': intentId,
        'handoff': handoff,
        'owner': rig.session.identity!.userId,
        'until': rig.now.add(const Duration(minutes: 5)).toIso8601String(),
      };
      for (final currency in ['USD', 'KHR']) {
        rig.model.details = {
          'intentId': intentId,
          'shopName': 'Sokha Coffee',
          'sourceAccount': '•••• 1234',
          'destinationAccount': '•••• 5678',
          'currency': currency,
          'amount': currency == 'USD' ? '12.50' : '25000',
          'status': 'PENDING',
          'expiresAt': rig.now
              .add(const Duration(minutes: 5))
              .toIso8601String(),
          'serverTime': rig.now.toIso8601String(),
        };
        for (final variant in [
          (name: 'phone-en', size: const Size(393, 852), scale: 1.0, km: false),
          (name: 'phone-km', size: const Size(393, 852), scale: 1.0, km: true),
          (name: 'small-en', size: const Size(320, 640), scale: 1.0, km: false),
          (name: 'large-km', size: const Size(320, 667), scale: 2.0, km: true),
          (
            name: 'landscape-en',
            size: const Size(812, 375),
            scale: 2.0,
            km: false,
          ),
          (
            name: 'tablet-km',
            size: const Size(800, 1280),
            scale: 1.3,
            km: true,
          ),
        ]) {
          tester.view.physicalSize = variant.size;
          for (final brightness in Brightness.values) {
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
                      padding: const EdgeInsets.only(top: 24, bottom: 24),
                    ),
                    child: RepaintBoundary(
                      key: key,
                      child: MerchantTransferApprovalScreen(
                        approval: rig.model,
                        session: rig.session,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final reason = '$currency ${variant.name} ${brightness.name}';
            expect(tester.takeException(), isNull, reason: reason);
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final rendered = await boundary.toImage(pixelRatio: 1);
              final bytes = await rendered.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '${directory.path}/transfer-$currency-${variant.name}-${brightness.name}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              rendered.dispose();
            });
            // The decline control stays reachable below the PIN field.
            await tester.scrollUntilVisible(
              find.byKey(const ValueKey('transfer-deny')),
              200,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('transfer-deny')).hitTestable(),
              findsOneWidget,
              reason: reason,
            );
            expect(tester.takeException(), isNull, reason: reason);
            await tester.pumpWidget(const SizedBox.shrink());
            prefs.dispose();
          }
        }
      }
      rig.dispose();
    },
  );
}
