import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the real v2 navigation: Sales moved from the tab bar to the drawer.
Future<void> openMerchantSection(WidgetTester tester, int section) async {
  tester
      .state<NavigatorState>(find.byType(Navigator).first)
      .popUntil((route) => route.isFirst);
  await tester.pumpAndSettle();
  if (section == 2) {
    await openMerchantMenu(tester, '5e757');
  } else {
    final target = find.byKey(
      ValueKey('merchant-tab-${section == 3 ? 2 : section}'),
    );
    if (target.evaluate().isEmpty) {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
    await tester.tap(
      find.byKey(ValueKey('merchant-tab-${section == 3 ? 2 : section}')),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> openMerchantMenu(WidgetTester tester, String asset) async {
  tester
      .state<NavigatorState>(find.byType(Navigator).first)
      .popUntil((route) => route.isFirst);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('merchant-menu')));
  await tester.pumpAndSettle();
  final row = find.byKey(ValueKey('merchant-menu-$asset'));
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}
