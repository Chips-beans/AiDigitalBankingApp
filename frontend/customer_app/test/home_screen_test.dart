import 'package:customer_app/features/home/presentation/kesor_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('balance visibility hides both amounts and restores them', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(440, 999);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: KesorHomeScreen(
          data: KesorHomeData.designPreview,
          showDeviceChrome: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(r'$168.00'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide balance'));
    await tester.pumpAndSettle();
    expect(find.text(r'$168.00'), findsNothing);
    expect(find.text(r'$••••'), findsOneWidget);
    await tester.tap(find.byTooltip('Show balance'));
    await tester.pumpAndSettle();
    expect(find.text(r'$168.00'), findsOneWidget);
  });

  testWidgets('Home controls call their existing navigation callbacks', (
    tester,
  ) async {
    int accounts = 0, transfers = 0, activity = 0, profile = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: KesorHomeScreen(
          data: KesorHomeData.designPreview,
          onAccounts: () => accounts++,
          onTransfer: () => transfers++,
          onActivity: () => activity++,
          onProfile: () => profile++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in [
      'View accounts',
      'Transfer',
      'Analytics',
      'Settings',
    ]) {
      await tester.tap(find.byTooltip(label).first);
      await tester.pumpAndSettle();
    }
    expect([accounts, transfers, activity, profile], [1, 1, 1, 1]);
  });

  for (final size in [
    const Size(375, 667),
    const Size(440, 999),
    const Size(667, 375),
  ]) {
    testWidgets(
      'Home stays scrollable and has no overflow at $size with large text',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(2),
              ),
              child: const KesorHomeScreen(
                data: KesorHomeData.designPreview,
                showDeviceChrome: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.drag(
          find.byKey(const PageStorageKey('kesor-home-scroll')),
          const Offset(0, -500),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byTooltip('Settings'), findsOneWidget);
      },
    );
  }
}
