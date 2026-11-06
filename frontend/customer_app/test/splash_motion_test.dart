import 'package:customer_app/shared/widgets/customer_splash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wallet_details_design_test.dart' show detailsHarness;

void main() {
  testWidgets('splash follows Figma hold, fade and scale timing', (
    tester,
  ) async {
    await tester.pumpWidget(detailsHarness(const CustomerSplash()));
    final opacity = find
        .descendant(
          of: find.byType(CustomerSplash),
          matching: find.byType(Opacity),
        )
        .first;
    final transform = find
        .descendant(
          of: find.byType(CustomerSplash),
          matching: find.byType(Transform),
        )
        .first;
    expect(tester.widget<Opacity>(opacity).opacity, 0);
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.widget<Opacity>(opacity).opacity, closeTo(0, .001));
    expect(
      tester.widget<Transform>(transform).transform.storage[0],
      closeTo(.88, .001),
    );
    await tester.pump(const Duration(milliseconds: 730));
    expect(tester.widget<Opacity>(opacity).opacity, closeTo(1, .001));
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester.widget<Transform>(transform).transform.storage[0],
      closeTo(1, .001),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion immediately displays the final brand mark', (
    tester,
  ) async {
    await tester.pumpWidget(
      detailsHarness(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: CustomerSplash(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final opacity = find
        .descendant(
          of: find.byType(CustomerSplash),
          matching: find.byType(Opacity),
        )
        .first;
    expect(tester.widget<Opacity>(opacity).opacity, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
