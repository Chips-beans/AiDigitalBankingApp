import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_app/app/merchant_app.dart';
import 'package:merchant_app/core/merchant_preferences.dart';
import 'package:merchant_app/core/merchant_splash.dart';
import 'package:merchant_app/features/auth/merchant_session.dart';

void main() {
  testWidgets(
    'startup splash waits for restoration, then yields to the session flow',
    (tester) async {
      final restoration = Completer<void>();
      final session = MerchantSession(UnavailableMerchantAuth());
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MerchantApp(
          preferences: MerchantPreferences(),
          session: session,
          startup: restoration.future,
        ),
      );
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.byType(MerchantSplash), findsOneWidget);
      restoration.complete();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(MerchantSplash), findsNothing);
      expect(find.text('Continue with Kesor Bank'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
