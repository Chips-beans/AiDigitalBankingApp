import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/app/design_system/design_system.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/auth/data/auth_gateway.dart';
import 'package:customer_app/features/auth/presentation/continuation_pages.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:customer_app/features/home/presentation/kesor_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    for (final family in {
      'Google Sans': [
        'GoogleSans-Regular.ttf',
        'GoogleSans-Medium.ttf',
        'GoogleSans-Bold.ttf',
      ],
      'Poppins': [
        'Poppins-Light.ttf',
        'Poppins-Regular.ttf',
        'Poppins-Medium.ttf',
        'Poppins-SemiBold.ttf',
      ],
      'Noto Sans Khmer': ['NotoSansKhmer-Variable.ttf'],
    }.entries) {
      final loader = FontLoader(family.key);
      for (final file in family.value) {
        loader.addFont(rootBundle.load('assets/fonts/$file'));
      }
      await loader.load();
    }
  });

  Future<void> show(
    WidgetTester tester,
    Widget page,
    Brightness mode,
    AppPreferences prefs,
    Size size, {
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      AppPreferencesScope(
        preferences: prefs,
        child: MaterialApp(
          key: ValueKey('$mode-${prefs.locale}-$size-$scale'),
          theme: AppTheme.build(mode, locale: prefs.locale),
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
            ),
            child: page,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'welcome matches reference geometry and does not resize when theme changes',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = SessionController(
        DemoAuthGateway(),
        MemorySessionVault(),
      );
      await session.initialize();
      addTearDown(session.dispose);
      final prefs = AppPreferences();
      addTearDown(prefs.dispose);
      for (final mode in Brightness.values) {
        await show(
          tester,
          ContinueWelcomePage(session),
          mode,
          prefs,
          const Size(440, 956),
        );
        final primary = find.byKey(const ValueKey('welcome-telegram'));
        final secondary = find.byKey(const ValueKey('welcome-email'));
        expect(tester.getSize(primary), const Size(400, 52));
        expect(tester.getSize(secondary), const Size(400, 52));
        expect(tester.getTopLeft(primary).dy, closeTo(726.2, .1));
        expect(
          tester.getTopLeft(secondary).dy - tester.getTopLeft(primary).dy,
          68,
        );
        expect(
          tester
              .getSize(find.byKey(const ValueKey('preference-capsule')))
              .height,
          44,
        );
        final style = tester
            .widget<FilledButton>(primary)
            .style!
            .textStyle!
            .resolve({})!;
        expect(style.fontFamily, AppTypography.khmerFamily);
        expect(style.fontWeight, FontWeight.w400);
        final scroll = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        expect(
          scroll.position.maxScrollExtent,
          0,
          reason: 'The full 956px reference must fit',
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Home keeps Figma card geometry in both themes and on desktop', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = AppPreferences()..locale = const Locale('km');
    addTearDown(prefs.dispose);
    for (final mode in Brightness.values) {
      for (final size in [const Size(440, 999), const Size(1200, 999)]) {
        await show(
          tester,
          const KesorHomeScreen(
            data: KesorHomeData.designPreview,
            showDeviceChrome: true,
          ),
          mode,
          prefs,
          size,
        );
        for (final item in [
          ('home-balance-card', const Size(400, 312), 132.0),
          ('home-recipients-card', const Size(400, 94), 510.0),
          ('home-transactions-card', const Size(400, 228), 664.0),
        ]) {
          final finder = find.byKey(ValueKey(item.$1));
          expect(
            tester.getSize(finder),
            item.$2,
            reason: '$mode $size ${item.$1}',
          );
          expect(tester.getTopLeft(finder).dx, (size.width - 440) / 2 + 20);
          expect(tester.getTopLeft(finder).dy, item.$3);
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'long recipient names stay within their slots and small screens scroll',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final prefs = AppPreferences();
      addTearDown(prefs.dispose);
      const name =
          'A very long recipient name that should never paint over its neighbours';
      const data = KesorHomeData(
        khrBalance: '2,000',
        usdBalance: r'$168',
        recipients: [HomeRecipient(name), HomeRecipient('Another recipient')],
      );
      for (final mode in Brightness.values) {
        for (final scale in [1.0, 2.0]) {
          await show(
            tester,
            const KesorHomeScreen(data: data),
            mode,
            prefs,
            const Size(320, 568),
            scale: scale,
          );
          final scrollBottom = tester
              .getBottomLeft(
                find.byKey(const PageStorageKey('kesor-home-scroll')),
              )
              .dy;
          final barTop = tester
              .getTopLeft(find.byKey(const ValueKey('kesor-nav-capsule')))
              .dy;
          expect(
            barTop - scrollBottom,
            greaterThanOrEqualTo(19),
            reason: 'Activity must not paint underneath the floating bar',
          );
          final label = find.text(name);
          final paragraph = tester.renderObject<RenderParagraph>(label);
          expect(paragraph.didExceedMaxLines, isTrue);
          expect(tester.getSize(label).width, lessThanOrEqualTo(144));
          await tester.drag(
            find.byKey(const PageStorageKey('kesor-home-scroll')),
            const Offset(0, -500),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
