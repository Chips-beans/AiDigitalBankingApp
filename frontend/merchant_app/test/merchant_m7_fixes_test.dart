import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_app/features/collect/collect_view.dart';
import 'package:merchant_app/features/collect/merchant_collect.dart';
import 'package:merchant_app/features/sales/receipt_page.dart';
import 'package:merchant_app/features/sales/reports_page.dart';
import 'package:merchant_app/features/sales/sales_controller.dart';
import 'package:merchant_app/features/sales/sales_view.dart';
import 'package:merchant_app/features/shop/merchant_shop.dart';
import 'package:merchant_app/features/shop/shop_widgets.dart';

import 'merchant_sales_test.dart'
    show harness, tall, receiptJson, receiptFixture, PagedGateway;
import 'merchant_shop_test.dart' show FakeShopGateway;

class BusyReportGateway extends FakeShopGateway {
  int reportCalls = 0;
  @override
  Future<CollectionReport> report({
    required String period,
    required String from,
    required String to,
  }) {
    if (++reportCalls == 1) {
      throw const ShopFailure('CONCURRENT_UPDATE', status: 409);
    }
    return super.report(period: period, from: from, to: to);
  }
}

void main() {
  test('receipt time always crosses Phnom Penh midnight independently of local time', () {
    expect(
      shortTime(DateTime.parse('2026-11-02T17:30:00Z')),
      '03/11/2026 00:30',
    );
    expect(
      shortTime(DateTime.parse('2026-11-02T12:30:00-05:00')),
      '03/11/2026 00:30',
    );
  });
  for (final km in [false, true]) {
    testWidgets(
      'exact human exchange rate appears in card and share text, km=$km',
      (tester) async {
        tall(tester);
        final receipt = receiptFixture();
        final rate = km ? '1 ដុល្លារ = 4,000 ៛' : '1 USD = 4,000 ៛';
        await tester.pumpWidget(
          harness(
            Scaffold(body: ReceiptCard(receipt: receipt)),
            km: km,
          ),
        );
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(ReceiptCard));
        expect(find.text(rate), findsOneWidget);
        expect(receiptShareText(context, receipt), contains(rate));
        expect(
          receiptShareText(context, receipt),
          isNot(contains('4000.0000')),
        );
        final fraction = ShopReceipt.fromJson({
          ...receiptJson(),
          'exchangeRate': '4000.1250',
        });
        expect(
          receiptExchangeRate(context, fraction),
          km ? '1 ដុល្លារ = 4,000.125 ៛' : '1 USD = 4,000.125 ៛',
        );
        final missing = ShopReceipt.fromJson({
          ...receiptJson(),
          'exchangeRate': null,
        });
        expect(receiptExchangeRate(context, missing), isNull);
        expect(receiptShareText(context, missing), isNot(contains(' = ')));
        await tester.pumpWidget(
          harness(
            Scaffold(body: ReceiptCard(receipt: missing)),
            km: km,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(rate), findsNothing);
        final same = ShopReceipt.fromJson({
          ...receiptJson(),
          'paidCurrency': 'KHR',
          'paidAmount': '25000',
        });
        expect(
          receiptExchangeRate(tester.element(find.byType(ReceiptCard)), same),
          isNull,
        );
        expect(
          receiptShareText(tester.element(find.byType(ReceiptCard)), same),
          isNot(contains(' = ')),
        );
      },
    );
  }
  testWidgets('payment counts use English singular and plural for 0, 1 and 2', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                for (final n in [0, 1, 2]) Text(paymentCount(context, n)),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('0 payments'), findsOneWidget);
    expect(find.text('1 payment'), findsOneWidget);
    expect(find.text('2 payments'), findsOneWidget);
  });
  testWidgets('Khmer payment count uses one form', (tester) async {
    await tester.pumpWidget(
      harness(
        Scaffold(
          body: Builder(builder: (context) => Text(paymentCount(context, 1))),
        ),
        km: true,
      ),
    );
    expect(find.text('ការទូទាត់ 1'), findsOneWidget);
  });
  testWidgets(
    'busy Sales page retries from the first page and matches tab title typography',
    (tester) async {
      tall(tester);
      final gateway = PagedGateway();
      final controller = SalesController(gateway);
      await tester.pumpWidget(
        harness(
          Scaffold(
            body: SalesView(controller: controller, onRequest: (_) async {}),
          ),
        ),
      );
      gateway.pending[0].complete(
        SalesPage(
          [receiptFixture()],
          'next',
          const [CurrencyTotal('KHR', 1, '25000')],
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text('Sales')).style!.fontSize, 20);
      expect(
        tester.widget<Text>(find.text('Sales')).style!.fontWeight,
        FontWeight.w600,
      );
      final more = controller.more();
      gateway.pending[1].completeError(
        const ShopFailure('CONCURRENT_UPDATE', status: 409),
      );
      await more;
      await tester.pumpAndSettle();
      expect(
        find.text('Your shop is busy updating. Please try again.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(gateway.calls.last.$2, isNull);
      expect(gateway.calls, hasLength(3));
      gateway.pending[2].complete(
        const SalesPage([], null, [
          CurrencyTotal('KHR', 0, '0'),
          CurrencyTotal('USD', 0, '0.00'),
        ]),
      );
      await tester.pumpAndSettle();
      expect(controller.failure, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
  testWidgets(
    'Reports busy notice offers a working refresh in English and Khmer',
    (tester) async {
      tall(tester);
      for (final km in [false, true]) {
        final gateway = BusyReportGateway();
        await tester.pumpWidget(
          harness(
            ReportsPage(key: ValueKey(km), gateway: gateway),
            km: km,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            km
                ? 'ហាងរបស់អ្នកកំពុងធ្វើបច្ចុប្បន្នភាព។ សូមព្យាយាមម្ដងទៀត។'
                : 'Your shop is busy updating. Please try again.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text(km ? 'ព្យាយាមម្ដងទៀត' : 'Try again'));
        await tester.pumpAndSettle();
        expect(gateway.reportCalls, 2);
        expect(find.text(km ? 'ការទូទាត់ 0' : '0 payments'), findsWidgets);
      }
    },
  );
}
