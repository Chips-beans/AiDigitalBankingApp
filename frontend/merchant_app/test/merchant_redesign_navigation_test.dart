import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_app/app/merchant_app.dart';
import 'package:merchant_app/core/merchant_preferences.dart';
import 'package:merchant_app/features/auth/merchant_session.dart';
import 'package:merchant_app/features/sales/sales_view.dart';
import 'package:merchant_app/features/sales/reports_page.dart';
import 'package:merchant_app/features/sales/requests_page.dart';
import 'package:merchant_app/features/collect/collect_view.dart';
import 'package:merchant_app/core/merchant_ui.dart';
import 'package:merchant_app/features/shop/shop_controller.dart';
import 'package:merchant_app/features/shop/shop_home.dart';
import 'package:merchant_app/features/shop/merchant_shop.dart';
import 'package:kesor_auth_handoff/kesor_auth_handoff.dart';

import 'merchant_foundation_test.dart' show ControlledMerchantAuth;
import 'merchant_shop_test.dart' show FakeShopGateway, readyProfile;

void main() {
  for (final khmer in [false, true]) {
    testWidgets(
      'Long identity and maximum amounts wrap at 320px and 2x, Khmer=$khmer',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final gateway = FakeShopGateway()
          ..profile = ShopProfile(
            onboardingState: 'READY',
            ownerName: 'Owner',
            shop: readyProfile(
              name: khmer
                  ? 'ហាងកាហ្វេកេសរ សាខាកណ្ដាលទីក្រុងភ្នំពេញ'
                  : 'Kesor Coffee and Bakery Central Phnom Penh',
            ).shop,
            wallets: const [
              ShopWallet(
                accountNumber: '1234567890',
                currency: 'USD',
                status: 'ACTIVE',
                balance: '9999999999999.99',
              ),
              ShopWallet(
                accountNumber: '2234567890',
                currency: 'KHR',
                status: 'ACTIVE',
                balance: '9999999999999',
              ),
            ],
          );
        final controller = ShopController(gateway, MemoryHandoffStore());
        await controller.initialize();
        await tester.pumpWidget(
          MaterialApp(
            theme: merchantTheme(Brightness.dark, Locale(khmer ? 'km' : 'en')),
            home: MerchantStrings(
              khmer: khmer,
              child: MediaQuery(
                data: const MediaQueryData(
                  size: Size(320, 640),
                  textScaler: TextScaler.linear(2),
                ),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: ShopHomeView(
                      controller: controller,
                      fallbackName: 'Shop',
                      onCollect: () {},
                      onSales: () {},
                      onEditShop: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final currency in ['USD', 'KHR']) {
          final amount = find.byKey(ValueKey('wallet-balance-$currency'));
          await tester.ensureVisible(amount);
          await tester.pumpAndSettle();
          expect(amount.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );
  }
  for (final destination in ['Sales', 'Shop QR', 'Reports', 'Requests']) {
    testWidgets('Home $destination opens the functional destination', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = ControlledMerchantAuth();
      final session = MerchantSession(auth);
      final signingIn = session.signIn();
      auth.approval.complete(
        const MerchantIdentity(
          ownerId: 7,
          shop: MerchantShop(
            id: 'MCH-AB23CD45',
            name: 'Kesor Coffee',
            active: true,
          ),
        ),
      );
      await signingIn;
      await tester.pumpWidget(
        MerchantApp(
          preferences: MerchantPreferences(),
          session: session,
          shopGateway: FakeShopGateway()..profile = readyProfile(),
        ),
      );
      await tester.pumpAndSettle();
      final action = find.text(destination);
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      switch (destination) {
        case 'Sales':
          expect(find.byType(SalesView), findsOneWidget);
          expect(find.byKey(const ValueKey('sales-search')), findsOneWidget);
        case 'Shop QR':
          expect(find.byType(MerchantShopQrPage), findsOneWidget);
          expect(find.byType(KesorQrCard), findsOneWidget);
        case 'Reports':
          expect(find.byType(ReportsPage), findsOneWidget);
          expect(find.text('Daily'), findsOneWidget);
          expect(find.text('Monthly'), findsOneWidget);
        case 'Requests':
          expect(find.byType(RequestsPage), findsOneWidget);
          expect(find.text('Waiting'), findsOneWidget);
          expect(find.text('Paid'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    });
  }
}
