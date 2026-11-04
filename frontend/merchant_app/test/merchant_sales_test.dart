import 'support/merchant_navigation.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kesor_design_system/kesor_design_system.dart';
import 'package:kesor_auth_handoff/kesor_auth_handoff.dart';
import 'package:merchant_app/app/merchant_app.dart';
import 'package:merchant_app/core/merchant_config.dart';
import 'package:merchant_app/core/merchant_preferences.dart';
import 'package:merchant_app/core/platform/image_share.dart';
import 'package:merchant_app/features/auth/merchant_session.dart';
import 'package:merchant_app/features/collect/merchant_collect.dart';
import 'package:merchant_app/features/collect/collect_controller.dart';
import 'package:merchant_app/features/sales/sales_controller.dart';
import 'package:merchant_app/features/sales/sales_view.dart';
import 'package:merchant_app/features/sales/receipt_page.dart';
import 'package:merchant_app/features/sales/reports_page.dart';
import 'package:merchant_app/features/shop/merchant_shop.dart';
import 'package:merchant_app/features/shop/merchant_shop_api.dart';

import 'merchant_foundation_test.dart' show ControlledMerchantAuth;
import 'merchant_shop_test.dart' show FakeShopGateway, readyProfile;

ShopReceipt receiptFixture([String reference = 'TXN-0001']) => ShopReceipt(
  reference: reference,
  currency: 'KHR',
  amount: '25000',
  paidCurrency: 'USD',
  paidAmount: '6.25',
  payerName: 'Sophea',
  payerAccount: '•••• 4321',
  paidAt: DateTime.parse('2026-11-03T10:00:00+07:00'),
  storeName: 'Original shop',
  walletAccountNumber: '1234567890',
  exchangeRate: '4000.0000',
  orderReference: 'Table 4',
  requestReference: 'PRABCDEFGH23',
);
Map<String, Object?> receiptJson() => {
  'reference': 'TXN-0001',
  'currency': 'KHR',
  'amount': '25000',
  'paidCurrency': 'USD',
  'paidAmount': '6.25',
  'payerName': 'Sophea',
  'payerAccount': '•••• 4321',
  'paidAt': '2026-11-03T10:00:00+07:00',
  'storeName': 'Original shop',
  'walletAccountNumber': '1234567890',
  'exchangeRate': '4000.0000',
  'requestReference': 'PRABCDEFGH23',
  'orderReference': 'Table 4',
};

class PagedGateway extends FakeShopGateway {
  final calls = <(SalesFilter, String?)>[];
  final pending = <Completer<SalesPage>>[];
  @override
  Future<SalesPage> sales(SalesFilter filter, {String? cursor}) {
    calls.add((filter, cursor));
    final c = Completer<SalesPage>();
    pending.add(c);
    return c.future;
  }
}

class Access implements MerchantAccess {
  @override
  Future<String> accessToken() async => 'merchant-token';
}

class RequestRaceGateway extends FakeShopGateway {
  String? slowId;
  final gate = Completer<PaymentRequest>();
  @override
  Future<PaymentRequest> requestStatus(String id) =>
      id == slowId ? gate.future : super.requestStatus(id);
}

void tall(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(480, 2600);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget harness(Widget child, {bool km = false}) => MaterialApp(
  locale: Locale(km ? 'km' : 'en'),
  supportedLocales: const [Locale('en'), Locale('km')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: AppTheme.build(Brightness.light, locale: Locale(km ? 'km' : 'en')),
  builder: (context, child) => MerchantStrings(khmer: km, child: child!),
  home: child,
);
Future<MerchantSession> signedIn() async {
  final auth = ControlledMerchantAuth();
  final session = MerchantSession(auth);
  final future = session.signIn();
  auth.approval.complete(
    const MerchantIdentity(
      ownerId: 7,
      shop: MerchantShop(
        id: 'MCH-AB23CD45',
        name: 'Current shop',
        active: true,
      ),
    ),
  );
  await future;
  return session;
}

void main() {
  testWidgets(
    'offline sales does not invent zero money or zero payment totals',
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
      gateway.pending.single.completeError(const ShopFailure('OFFLINE'));
      await tester.pumpAndSettle();
      expect(find.text('—'), findsNWidgets(2));
      expect(find.text('0 ៛'), findsNothing);
      expect(find.text(r'$0.00'), findsNothing);
      expect(find.text('0 payments'), findsNothing);
      expect(find.textContaining('Connect to the internet'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
  test(
    'opening history ignores success or failure of an older request poll',
    () async {
      for (final fail in [false, true]) {
        final gateway = RequestRaceGateway();
        final collect = CollectController(
          gateway,
          MemoryHandoffStore(),
          pollEvery: const Duration(hours: 1),
        );
        await collect.create(currency: 'KHR', amount: '500');
        final old = collect.request!;
        gateway.slowId = old.id;
        final stale = collect.refresh();
        final next = await gateway.createRequest(
          'new-key',
          currency: 'USD',
          amount: '1.00',
        );
        await collect.openRequest(next.id);
        if (fail) {
          gateway.gate.completeError(const ShopFailure('OFFLINE'));
        } else {
          gateway.gate.complete(old);
        }
        await stale;
        expect(collect.request!.id, next.id);
        expect(collect.reconnecting, isFalse);
        expect(collect.waiting, isTrue);
        collect.dispose();
      }
    },
  );
  test(
    'paging deduplicates overlapping references and keeps whole filter totals',
    () async {
      final gateway = PagedGateway();
      final c = SalesController(gateway);
      final first = c.refresh();
      gateway.pending[0].complete(
        SalesPage(
          [receiptFixture('A'), receiptFixture('B')],
          'cursor',
          const [CurrencyTotal('KHR', 3, '75000')],
        ),
      );
      await first;
      final next = c.more();
      expect(gateway.calls.last.$2, 'cursor');
      gateway.pending[1].complete(
        SalesPage(
          [receiptFixture('B'), receiptFixture('C')],
          null,
          const [CurrencyTotal('KHR', 3, '75000')],
        ),
      );
      await next;
      expect(c.items.map((r) => r.reference), ['A', 'B', 'C']);
      expect(c.totals.single.gross, '75000');
      expect(c.nextCursor, isNull);
      c.dispose();
    },
  );
  test(
    'a late page from an old filter cannot append or replace current results',
    () async {
      final gateway = PagedGateway();
      final c = SalesController(gateway);
      final first = c.refresh();
      gateway.pending[0].complete(
        SalesPage([receiptFixture('A')], 'old', const []),
      );
      await first;
      final old = c.more();
      final changed = c.change(
        const SalesFilter(
          from: '2026-11-01',
          to: '2026-11-03',
          currency: 'USD',
          q: 'new',
        ),
      );
      gateway.pending[2].complete(
        SalesPage([receiptFixture('New')], null, const []),
      );
      await changed;
      gateway.pending[1].complete(
        SalesPage([receiptFixture('Old')], 'more-old', const []),
      );
      await old;
      expect(c.items.single.reference, 'New');
      expect(c.nextCursor, isNull);
      expect(c.loading, isFalse);
      c.dispose();
    },
  );
  test(
    'old filter errors and disposed responses cannot revive private data',
    () async {
      final gateway = PagedGateway();
      var expired = 0;
      final c = SalesController(gateway, onExpired: () => expired++);
      final old = c.refresh();
      final current = c.change(
        const SalesFilter(from: '2026-11-02', to: '2026-11-03'),
      );
      gateway.pending[0].completeError(
        const ShopFailure('SESSION_INVALID', status: 401),
      );
      await old;
      expect(expired, 0);
      expect(c.failure, isNull);
      expect(c.loading, isTrue);
      c.dispose();
      gateway.pending[1].complete(
        SalesPage([receiptFixture()], null, const []),
      );
      await current;
      expect(c.items, isEmpty);
    },
  );
  test('receipt parsing preserves exact money and snapshot fields and refuses private payer account', () {
    final r = ShopReceipt.fromJson(receiptJson());
    expect(r.amount, '25000');
    expect(r.paidAmount, '6.25');
    expect(r.storeName, 'Original shop');
    expect(r.exchangeRate, '4000.0000');
    expect(r.paidAt.toUtc(), DateTime.utc(2026, 11, 3, 3));
    for (final change in [
      {'currency': 'EUR'},
      {'paidCurrency': 'EUR'},
      {'amount': 25000},
      {'amount': '25000.5'},
      {'paidAmount': '6.250'},
      {'payerAccount': '1234567890'},
      {'paidAt': '2026-11-03T10:00:00'},
      {'reference': null},
      {'storeName': null},
      {'walletAccountNumber': null},
      {'walletAccountNumber': '1'},
    ]) {
      expect(
        () => ShopReceipt.fromJson({...receiptJson(), ...change}),
        throwsA(isA<ShopFailure>()),
      );
    }
    expect(
      () => RequestHistory.fromJson({
        'items': [
          {'status': 'UNKNOWN'},
        ],
      }),
      throwsA(isA<ShopFailure>()),
    );
    expect(
      () => CollectionReport.fromJson({
        'period': 'YEAR',
        'buckets': [],
        'totals': [],
      }),
      throwsA(isA<ShopFailure>()),
    );
  });
  test('business dates and grouped sums are independent of device zone and exact for large amounts', () {
    expect(
      dateKey(businessTime(DateTime.parse('2026-11-02T17:01:00Z'))),
      '2026-11-03',
    );
    expect(
      unitsMoney(
        moneyUnits('9999999999999.99', 'USD') + moneyUnits('0.01', 'USD'),
        'USD',
      ),
      '10000000000000.00',
    );
  });
  test('sales report receipt and request APIs encode filters with Merchant authorization', () async {
    final seen = <http.Request>[];
    final api = MerchantShopApi(
      MerchantConfig(
        apiBaseUrl: 'http://localhost:8080/api/v1',
        environment: 'dev',
      ),
      Access(),
      client: MockClient((request) async {
        seen.add(request);
        final path = request.url.path;
        final Object data = path.endsWith('/sales')
            ? {
                'items': [receiptJson()],
                'nextCursor': null,
                'totals': [
                  {'currency': 'KHR', 'count': 1, 'gross': '25000'},
                  {'currency': 'USD', 'count': 0, 'gross': '0.00'},
                ],
              }
            : path.contains('/sales/')
            ? receiptJson()
            : path.endsWith('/collections')
            ? {
                'period': 'DAY',
                'buckets': [
                  {
                    'bucket': '2026-11-03',
                    'currency': 'KHR',
                    'count': 0,
                    'gross': '0',
                  },
                ],
                'totals': [
                  {'currency': 'KHR', 'count': 0, 'gross': '0'},
                ],
              }
            : {'items': [], 'nextCursor': null};
        return http.Response(
          jsonEncode({'success': true, 'data': data}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final page = await api.sales(
      const SalesFilter(
        from: '2026-11-01',
        to: '2026-11-03',
        currency: 'KHR',
        q: 'Table & 4',
      ),
      cursor: 'opaque_cursor',
    );
    expect(page.items.single.amount, '25000');
    expect(seen.last.url.queryParameters['q'], 'Table & 4');
    expect(seen.last.url.queryParameters['cursor'], 'opaque_cursor');
    expect((await api.receipt('TXN-0001')).storeName, 'Original shop');
    await api.report(period: 'DAY', from: '2026-11-01', to: '2026-11-03');
    await api.requestHistory(status: RequestStatus.expired, cursor: 'opaque');
    expect(seen.last.url.queryParameters['status'], 'EXPIRED');
    expect(
      seen.every((r) => r.headers['Authorization'] == 'Bearer merchant-token'),
      isTrue,
    );
  });
  testWidgets(
    'report renders zero filled daily and monthly buckets in both currencies',
    (tester) async {
      tall(tester);
      final gateway = FakeShopGateway()..profile = readyProfile();
      await tester.pumpWidget(harness(ReportsPage(gateway: gateway)));
      await tester.pumpAndSettle();
      expect(find.text('0 ៛'), findsWidgets);
      expect(find.text('0 payments'), findsWidgets);
      await tester.tap(find.text('Monthly'));
      await tester.pumpAndSettle();
      expect(find.text(dateKey(businessToday()).substring(0, 7)), findsWidgets);
      await tester.tap(find.text('USD'));
      await tester.pumpAndSettle();
      expect(find.text(r'$0.00'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'receipt uses snapshot name, full reference, masked wallet and safe text',
    (tester) async {
      tall(tester);
      final gateway = FakeShopGateway()
        ..profile = readyProfile(name: 'Changed shop')
        ..recent = [receiptFixture()];
      await tester.pumpWidget(
        harness(ReceiptPage(gateway: gateway, reference: 'TXN-0001')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Original shop'), findsOneWidget);
      expect(find.text('Changed shop'), findsNothing);
      expect(find.text('TXN-0001'), findsOneWidget);
      expect(find.text('KHR •••• 7890'), findsOneWidget);
      final context = tester.element(find.byType(ReceiptCard));
      final text = receiptShareText(context, receiptFixture());
      expect(text, contains('25,000'));
      expect(text, contains('•••• 4321'));
      expect(text, contains('TXN-0001'));
      expect(text, isNot(contains('1234567890')));
    },
  );
  testWidgets('share bridge failures have clear English and Khmer messages', (
    tester,
  ) async {
    tall(tester);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    var nativeCall = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(merchantShareChannel, (call) async {
          final args = call.arguments as Map;
          expect((args['png'] as List).take(4), [137, 80, 78, 71]);
          if (call.method == 'shareImage') {
            expect(args['text'], contains('TXN-0001'));
            expect(args['text'], isNot(contains('1234567890')));
          }
          nativeCall.complete();
          throw PlatformException(
            code: call.method == 'saveImage'
                ? 'UNSUPPORTED_ANDROID'
                : 'APP_UNAVAILABLE',
          );
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(merchantShareChannel, null),
    );
    for (final km in [false, true]) {
      await tester.pumpWidget(
        harness(
          Scaffold(
            body: Builder(
              builder: (context) => ImageActions(
                key: ValueKey(km),
                cardKey: GlobalKey(),
                name: 'kesor-receipt',
                receipt: true,
                text: receiptShareText(context, receiptFixture()),
                capture: (_) async =>
                    Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
              ),
            ),
          ),
          km: km,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('share-image')));
      await tester.pumpAndSettle();
      expect(nativeCall.isCompleted, isTrue);
      expect(
        find.text(
          km
              ? 'គ្មានកម្មវិធីសម្រាប់ចែករំលែករូបភាពទេ។'
              : 'No app is available to share images.',
        ),
        findsOneWidget,
      );
      nativeCall = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('save-image')));
      await tester.pumpAndSettle();
      expect(nativeCall.isCompleted, isTrue);
      expect(
        find.textContaining(
          km ? 'Android 10' : 'Saving to gallery needs Android 10',
        ),
        findsOneWidget,
      );
      nativeCall = Completer<void>();
    }
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('receipt capture exports a real PNG from only the public card', (
    tester,
  ) async {
    tall(tester);
    final key = GlobalKey();
    await tester.pumpWidget(
      harness(
        Scaffold(
          body: RepaintBoundary(
            key: key,
            child: ReceiptCard(receipt: receiptFixture()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final png = await tester.runAsync(() => captureCard(key));
    expect(png!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(png.length, greaterThan(1000));
  });
  testWidgets(
    'Sales opens receipts and request history can resume a waiting request',
    (tester) async {
      tall(tester);
      final session = await signedIn();
      final prefs = MerchantPreferences();
      final gateway = FakeShopGateway()..profile = readyProfile();
      gateway.recent = [
        ShopReceipt(
          reference: 'TXN-0001',
          currency: 'KHR',
          amount: '25000',
          paidCurrency: 'USD',
          paidAmount: '6.25',
          payerName: 'Sophea',
          payerAccount: '•••• 4321',
          paidAt: DateTime.now(),
          storeName: 'Original shop',
        ),
      ];
      await gateway.createRequest('k' * 20, currency: 'KHR', amount: '500');
      await tester.pumpWidget(
        MerchantApp(preferences: prefs, session: session, shopGateway: gateway),
      );
      await tester.pumpAndSettle();
      await openMerchantSection(tester, 2);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sophea · •••• 4321'));
      await tester.pumpAndSettle();
      expect(find.text('Original shop'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await openMerchantMenu(tester, 'dc524');
      await tester.pumpAndSettle();
      await tester.tap(find.text('500 ៛'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('request-qr')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      prefs.dispose();
    },
  );
}
