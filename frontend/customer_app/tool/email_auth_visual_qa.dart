import 'dart:io';
import 'dart:ui' as ui;

import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/auth/data/auth_gateway.dart';
import 'package:customer_app/features/auth/presentation/auth_pages.dart';
import 'package:customer_app/features/auth/presentation/continuation_pages.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class DesignAuthGateway extends DemoAuthGateway {
  @override
  Future<OtpReceipt> requestContinueOtp(
    String email, {
    String? linkToken,
  }) async => const OtpReceipt(resendAfterSeconds: 180);
}

void main() {
  testWidgets(
    'render all three email auth frames, themes, languages and adaptive layouts',
    (tester) async {
      await tester.runAsync(() async {
        for (final entry in {
          'Poppins': [
            'Poppins-Regular.ttf',
            'Poppins-Medium.ttf',
            'Poppins-SemiBold.ttf',
          ],
          'Google Sans': [
            'GoogleSans-Regular.ttf',
            'GoogleSans-Medium.ttf',
            'GoogleSans-Bold.ttf',
          ],
          'Noto Sans Khmer': ['NotoSansKhmer-Variable.ttf'],
          'MaterialIcons': ['MaterialIcons-Regular.otf'],
        }.entries) {
          final loader = FontLoader(entry.key);
          for (final file in entry.value) {
            loader.addFont(
              rootBundle.load(
                file.endsWith('.otf') ? 'fonts/$file' : 'assets/fonts/$file',
              ),
            );
          }
          await loader.load();
        }
      });
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final fixture in [
        for (final dark in [false, true])
          for (final km in [false, true])
            (
              name: '${dark ? 'dark' : 'light'}-${km ? 'km' : 'en'}',
              dark: dark,
              km: km,
              size: const Size(440, 956),
              scale: 1.0,
            ),
        (
          name: 'small-light-en',
          dark: false,
          km: false,
          size: const Size(375, 812),
          scale: 1.0,
        ),
        (
          name: 'large-text-dark-km',
          dark: true,
          km: true,
          size: const Size(375, 667),
          scale: 2.0,
        ),
        (
          name: 'landscape-dark-en',
          dark: true,
          km: false,
          size: const Size(812, 375),
          scale: 1.0,
        ),
        (
          name: 'tablet-light-en',
          dark: false,
          km: false,
          size: const Size(1024, 768),
          scale: 1.0,
        ),
      ]) {
        tester.view.physicalSize = fixture.size;
        tester.view.devicePixelRatio = 1;
        final prefs = AppPreferences()
          ..locale = Locale(fixture.km ? 'km' : 'en');
        final session = SessionController(
          DesignAuthGateway(),
          MemorySessionVault(),
          clock: () => DateTime(2026, 10, 30, 12),
        );
        await session.initialize();
        session.openEmail();
        for (final screen in ['email', 'verification', 'profile']) {
          if (screen == 'verification') {
            await session.beginEmail('example@gmail.com');
          }
          if (screen == 'profile') await session.verifyCode('123456');
          final key = GlobalKey();
          await tester.pumpWidget(
            AppPreferencesScope(
              preferences: prefs,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: prefs.locale,
                supportedLocales: const [Locale('en'), Locale('km')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                theme: AppTheme.build(
                  fixture.dark ? Brightness.dark : Brightness.light,
                  locale: prefs.locale,
                ),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: fixture.size,
                    textScaler: TextScaler.linear(fixture.scale),
                    disableAnimations: true,
                  ),
                  child: RepaintBoundary(
                    key: key,
                    child: ListenableBuilder(
                      listenable: session,
                      builder: (context, _) => screen == 'email'
                          ? EmailContinuePage(session, showDeviceChrome: true)
                          : screen == 'verification'
                          ? OtpPage(
                              session,
                              demo: false,
                              showDeviceChrome: true,
                            )
                          : InformationPage(session, showDeviceChrome: true),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (screen == 'verification') {
            await tester.enterText(find.byKey(const ValueKey('otpCode')), '1');
            await tester.pump();
          }
          if (screen == 'profile') {
            await tester.enterText(
              find.byKey(const ValueKey('firstName')),
              fixture.km ? 'ដារ៉ា' : 'Dara',
            );
            await tester.enterText(
              find.byKey(const ValueKey('lastName')),
              fixture.km ? 'សុខ' : 'Sok',
            );
            FocusManager.instance.primaryFocus?.unfocus();
            final scrollable = tester.state<ScrollableState>(
              find
                  .ancestor(
                    of: find.byKey(const ValueKey('profile-photo-card')),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            scrollable.position.jumpTo(0);
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('profile-photo-initial')),
              findsOneWidget,
            );
          }
          expect(
            tester.takeException(),
            isNull,
            reason: '${fixture.name} $screen',
          );
          if (fixture.size.width == 440 &&
              !fixture.km &&
              fixture.scale == 1 &&
              screen == 'email') {
            expect(tester.getTopLeft(find.text('Email address')).dx, 24);
            expect(tester.getTopLeft(find.text('Email address')).dy, 147);
            expect(
              tester.getSize(find.byKey(const ValueKey('email'))).width,
              392,
            );
            expect(
              tester.getTopLeft(find.text('Send Code')).dy,
              closeTo(273, 2),
            );
          }
          await tester.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            image.dispose();
            final file = File(
              '.local/qa/email-auth/$screen-${fixture.name}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
          });
          // Verify the final action is reachable even when the content scrolls.
          await tester.ensureVisible(
            find.text(
              screen == 'email'
                  ? (fixture.km ? 'ផ្ញើលេខកូដ' : 'Send Code')
                  : screen == 'verification'
                  ? (fixture.km ? 'ផ្ទៀងផ្ទាត់' : 'Verify')
                  : (fixture.km ? 'បង្កើតគណនី' : 'Create Account'),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
        session.dispose();
        prefs.dispose();
      }
    },
  );
}
