import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kesor_auth_handoff/kesor_auth_handoff.dart';
import 'package:kesor_design_system/kesor_design_system.dart';
import 'package:merchant_app/core/merchant_strings.dart';
import 'package:merchant_app/core/merchant_ui.dart';
import 'package:merchant_app/features/collect/collect_controller.dart';
import 'package:merchant_app/features/collect/collect_view.dart';
import 'package:merchant_app/features/shop/shop_controller.dart';
import 'package:merchant_app/features/shop/shop_home.dart';
import 'package:merchant_app/features/shop/merchant_shop.dart';

import 'merchant_shop_test.dart' show FakeShopGateway, readyProfile;

Widget host(Widget child) => MaterialApp(
  theme: AppTheme.build(Brightness.light),
  home: MerchantStrings(
    khmer: false,
    child: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  testWidgets('selected filter labels keep text contrast in both themes', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: merchantTheme(brightness, const Locale('en')),
            home: Scaffold(
              body: Wrap(
                children: [
                  ChoiceChip(
                    label: const Text('Today'),
                    selected: true,
                    onSelected: (_) {},
                  ),
                  ChoiceChip(
                    label: const Text('Yesterday'),
                    selected: false,
                    onSelected: (_) {},
                  ),
                  ChoiceChip(
                    label: const Text('All'),
                    selected: true,
                    onSelected: (_) {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      }
    } finally {
      handle.dispose();
    }
  });

  testWidgets(
    'numeric keypad submits the exact USD decimal and enforces cents',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(480, 2600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final gateway = FakeShopGateway();
      final collect = CollectController(gateway, MemoryHandoffStore());

      await tester.pumpWidget(
        host(
          CollectView(
            controller: collect,
            gateway: gateway,
            storeName: 'Kesor Coffee',
            active: true,
          ),
        ),
      );
      await tester.tap(find.text('USD'));
      await tester.pump();
      for (final digit in ['1', '2', '.', '5', '0', '9']) {
        await tester.tap(find.widgetWithText(TextButton, digit));
        await tester.pump();
      }
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('collect-amount')))
            .controller!
            .text,
        '12.50',
      );
      await tester.tap(find.byKey(const ValueKey('collect-create')));
      await tester.pump();
      expect(gateway.requests.values.single.currency, 'USD');
      expect(gateway.requests.values.single.amount, '12.50');
      expect(find.byKey(const ValueKey('request-qr')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      collect.dispose();
    },
  );

  testWidgets(
    'note and keypad remain reachable above a keyboard at large Khmer text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      final gateway = FakeShopGateway();
      final controller = CollectController(gateway, MemoryHandoffStore());
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: merchantTheme(Brightness.light, const Locale('km')),
          home: MerchantStrings(
            khmer: true,
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 640),
                textScaler: TextScaler.linear(2),
                viewInsets: EdgeInsets.only(bottom: 280),
              ),
              child: Scaffold(
                body: CollectView(
                  controller: controller,
                  gateway: gateway,
                  storeName: 'ហាងកាហ្វេកេសរ',
                  active: true,
                ),
              ),
            ),
          ),
        ),
      );
      final note = find.byKey(const ValueKey('collect-order'));
      await tester.ensureVisible(note);
      await tester.pump();
      await tester.enterText(note, 'តុលេខ ៤');
      await tester.pump();
      final button = find.byKey(const ValueKey('collect-create'));
      await tester.ensureVisible(button);
      await tester.pump();
      expect(tester.getRect(button).bottom, lessThanOrEqualTo(360));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('wrapped order label stays attached to the editable value', (
    tester,
  ) async {
    final gateway = FakeShopGateway();
    final controller = CollectController(gateway, MemoryHandoffStore());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        CollectView(
          controller: controller,
          gateway: gateway,
          storeName: 'Kesor Coffee',
          active: true,
        ),
      ),
    );
    final semantics = tester.ensureSemantics();
    try {
      final field = find.byKey(const ValueKey('collect-order'));
      await tester.enterText(field, 'Table 4');
      await tester.pump();
      final data = tester.getSemantics(field).getSemanticsData();
      expect(data.label, contains('Order note (optional)'));
      expect(data.value, 'Table 4');
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('wallet opens by keyboard and copy remains a separate action', (
    tester,
  ) async {
    var opened = 0;
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final wallet = readyProfile().wallets.first;
    await tester.pumpWidget(
      host(WalletTile(wallet: wallet, onTap: () => opened++)),
    );
    final semantics = tester.ensureSemantics();
    try {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(opened, 1);
      await tester.tap(find.byTooltip('Copy account number'));
      await tester.pumpAndSettle();
      expect(copied, wallet.accountNumber);
      expect(opened, 1);
      expect(find.text('Account number copied'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('refresh failure keeps balances visible and offers retry', (
    tester,
  ) async {
    final gateway = FakeShopGateway()..profile = readyProfile();
    final controller = ShopController(gateway, MemoryHandoffStore());
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.failure = const ShopFailure('OFFLINE');
    await tester.pumpWidget(
      host(
        ShopHomeView(
          controller: controller,
          fallbackName: 'Kesor Coffee',
          onCollect: () {},
          onSales: () {},
          onEditShop: () {},
        ),
      ),
    );
    expect(find.textContaining('You’re offline.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byKey(const ValueKey('wallet-balance-KHR')), findsOneWidget);
    expect(find.byKey(const ValueKey('wallet-balance-USD')), findsOneWidget);
    expect(find.byKey(const ValueKey('today-KHR')), findsOneWidget);
  });
}
