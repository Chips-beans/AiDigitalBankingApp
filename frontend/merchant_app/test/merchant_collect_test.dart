import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kesor_auth_handoff/kesor_auth_handoff.dart';
import 'package:merchant_app/app/merchant_app.dart';
import 'package:merchant_app/core/merchant_config.dart';
import 'package:merchant_app/core/merchant_preferences.dart';
import 'package:merchant_app/features/auth/merchant_session.dart';
import 'package:merchant_app/features/collect/collect_controller.dart';
import 'package:merchant_app/features/collect/merchant_collect.dart';
import 'package:merchant_app/features/shop/merchant_shop.dart';
import 'package:merchant_app/features/shop/merchant_shop_api.dart';

import 'merchant_foundation_test.dart' show ControlledMerchantAuth;
import 'merchant_shop_test.dart' show FakeShopGateway, readyProfile;

class _Access implements MerchantAccess {
  @override
  Future<String> accessToken() async => 'access-token';
}

void main() {
  group('collect controller', () {
    test('a paid request is shown once, refreshes the shop and clears the saved ID', () async {
      final gateway = FakeShopGateway()..profile = readyProfile();
      final store = MemoryHandoffStore();
      var paid = 0;
      final collect = CollectController(
        gateway,
        store,
        ownerId: 7,
        pollEvery: const Duration(milliseconds: 10),
        onPaid: () => paid++,
      );
      expect(await collect.create(currency: 'KHR', amount: '25000'), isTrue);
      final id = collect.request!.id;
      expect(store.values['collect-7'], id);
      expect(collect.remaining, lessThanOrEqualTo(const Duration(minutes: 5)));
      gateway.pay(id);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(collect.request!.status, RequestStatus.paid);
      expect(collect.request!.receipt!.payerName, 'Sophea');
      expect(paid, 1);
      expect(store.values.containsKey('collect-7'), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(paid, 1);
      collect.dispose();
    });

    test(
      'an uncertain create keeps the key; a rejection or new amount does not',
      () async {
        final gateway = FakeShopGateway()..profile = readyProfile();
        final collect = CollectController(gateway, MemoryHandoffStore());
        gateway.nextCreate = const ShopFailure('TIMEOUT');
        expect(await collect.create(currency: 'USD', amount: '6.25'), isFalse);
        expect(collect.failure!.uncertain, isTrue);
        expect(await collect.create(currency: 'USD', amount: '6.25'), isTrue);
        expect(gateway.createKeys[1], gateway.createKeys[0]);
        await collect.cancel();
        await collect.reset();

        gateway.nextCreate = const ShopFailure('INVALID_AMOUNT', status: 400);
        expect(await collect.create(currency: 'USD', amount: '1.00'), isFalse);
        expect(await collect.create(currency: 'USD', amount: '1.00'), isTrue);
        expect(gateway.createKeys[3], isNot(gateway.createKeys[2]));
        collect.dispose();
      },
    );

    test('cancel shows a payment that won the race', () async {
      final gateway = FakeShopGateway()..profile = readyProfile();
      final collect = CollectController(
        gateway,
        MemoryHandoffStore(),
        pollEvery: const Duration(hours: 1),
      );
      await collect.create(currency: 'KHR', amount: '1000');
      gateway.pay(collect.request!.id);
      await collect.cancel();
      expect(collect.request!.status, RequestStatus.paid);
      expect(gateway.cancels, 1);
      collect.dispose();
    });

    test('a restarted app resumes watching the saved request', () async {
      final gateway = FakeShopGateway()..profile = readyProfile();
      final store = MemoryHandoffStore();
      final first = CollectController(
        gateway,
        store,
        ownerId: 7,
        pollEvery: const Duration(hours: 1),
      );
      await first.create(currency: 'KHR', amount: '5000');
      first.dispose();
      final restarted = CollectController(
        gateway,
        store,
        ownerId: 7,
        pollEvery: const Duration(hours: 1),
      );
      await restarted.resume();
      expect(restarted.waiting, isTrue);
      expect(restarted.request!.amount, '5000');
      final other = CollectController(gateway, store, ownerId: 8);
      await other.resume();
      expect(other.request, isNull);
      restarted.dispose();
      other.dispose();
    });

    test('lost polls keep waiting; an expired session is reported', () async {
      final gateway = FakeShopGateway()..profile = readyProfile();
      var expired = 0;
      final collect = CollectController(
        gateway,
        MemoryHandoffStore(),
        pollEvery: const Duration(hours: 1),
        onExpired: () => expired++,
      );
      await collect.create(currency: 'USD', amount: '2.00');
      gateway.nextStatus = const ShopFailure('OFFLINE');
      await collect.refresh();
      expect(collect.reconnecting, isTrue);
      expect(collect.waiting, isTrue);
      gateway.nextStatus = const ShopFailure('SESSION_INVALID', status: 401);
      await collect.refresh();
      expect(expired, 1);
      collect.dispose();
    });
  });

  group('collect API', () {
    final config = MerchantConfig(
      apiBaseUrl: 'http://localhost:8080/api/v1',
      environment: 'dev',
    );
    Map<String, dynamic> view(String status) => {
      'requestId': '11111111-1111-4111-8111-111111111111',
      'reference': 'PRABCDEFGH23',
      'status': status,
      'currency': 'KHR',
      'amount': '25000',
      'orderReference': 'Table 4',
      'qrString': status == 'WAITING' ? '000201010212' : null,
      'createdAt': '2026-11-03T10:00:00+07:00',
      'expiresAt': '2026-11-03T10:05:00+07:00',
      'serverTime': '2026-11-03T10:01:00+07:00',
      'receipt': null,
    };

    test(
      'requests carry the key, exact amount text and parse server time',
      () async {
        late http.Request seen;
        final api = MerchantShopApi(
          config,
          _Access(),
          client: MockClient((request) async {
            seen = request;
            return http.Response(
              jsonEncode({'success': true, 'data': view('WAITING')}),
              201,
            );
          }),
        );
        final r = await api.createRequest(
          'key-1234567890abcdef',
          currency: 'KHR',
          amount: '25000',
          orderReference: 'Table 4',
        );
        expect(seen.headers['Idempotency-Key'], 'key-1234567890abcdef');
        expect(jsonDecode(seen.body), {
          'currency': 'KHR',
          'amount': '25000',
          'orderReference': 'Table 4',
        });
        expect(r.status, RequestStatus.waiting);
        expect(r.remainingAtFetch, const Duration(minutes: 4));
      },
    );

    test('unknown statuses and malformed IDs fail closed', () async {
      final api = MerchantShopApi(
        config,
        _Access(),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'success': true, 'data': view('SETTLED')}),
            200,
          ),
        ),
      );
      await expectLater(
        api.requestStatus('11111111-1111-4111-8111-111111111111'),
        throwsA(
          isA<ShopFailure>().having((f) => f.code, 'code', 'INVALID_RESPONSE'),
        ),
      );
      await expectLater(
        api.requestStatus('../wallets'),
        throwsA(isA<ShopFailure>()),
      );
      await expectLater(api.wallet('12/34'), throwsA(isA<ShopFailure>()));
    });
  });

  group('screens', () {
    Future<MerchantSession> signedIn() async {
      final auth = ControlledMerchantAuth();
      final session = MerchantSession(auth);
      final pending = session.signIn();
      auth.approval.complete(
        const MerchantIdentity(
          ownerId: 7,
          shop: MerchantShop(id: 'MCH-AB23CD45', name: 'Kesor Coffee'),
        ),
      );
      await pending;
      return session;
    }

    void tall(WidgetTester tester) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(480, 2600);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets(
      'collect validates, shows a live QR and then the confirmed payment',
      (tester) async {
        tall(tester);
        final session = await signedIn();
        final gateway = FakeShopGateway()..profile = readyProfile();
        final prefs = MerchantPreferences();
        await tester.pumpWidget(
          MerchantApp(
            preferences: prefs,
            session: session,
            shopGateway: gateway,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(NavigationDestination).at(1));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('collect-amount')),
          // The KHR field only accepts digits; zero is still rejected.
          '000',
        );
        await tester.tap(find.byKey(const ValueKey('collect-create')));
        await tester.pumpAndSettle();
        expect(find.text('Enter a whole riel amount'), findsOneWidget);
        expect(gateway.createKeys, isEmpty);

        await tester.enterText(
          find.byKey(const ValueKey('collect-amount')),
          '25000',
        );
        await tester.enterText(
          find.byKey(const ValueKey('collect-order')),
          'Table 4',
        );
        await tester.tap(find.byKey(const ValueKey('collect-create')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byKey(const ValueKey('request-qr')), findsOneWidget);
        expect(find.text('25,000 ៛'), findsOneWidget);
        expect(find.text('Waiting for payment'), findsOneWidget);
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('request-countdown')))
              .data,
          anyOf('5:00', '4:59'),
        );

        gateway.pay(gateway.requests.keys.single);
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byKey(const ValueKey('request-paid')), findsOneWidget);
        expect(find.text('Payment received'), findsOneWidget);
        expect(find.textContaining('Sophea'), findsOneWidget);
        expect(find.text(r'$6.25'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('request-new')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('collect-create')), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        session.dispose();
        prefs.dispose();
      },
    );

    testWidgets('shop QR mode shows the reusable QR for the chosen currency', (
      tester,
    ) async {
      tall(tester);
      final session = await signedIn();
      final gateway = FakeShopGateway()..profile = readyProfile();
      final prefs = MerchantPreferences();
      await tester.pumpWidget(
        MerchantApp(preferences: prefs, session: session, shopGateway: gateway),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(NavigationDestination).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shop QR'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('shop-qr')), findsOneWidget);
      expect(find.text('1234567890'), findsOneWidget);
      await tester.tap(find.text(r'USD $'));
      await tester.pumpAndSettle();
      expect(find.text('2234567890'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      prefs.dispose();
    });

    testWidgets(
      'home lists recent payments and opens a wallet with its activity',
      (tester) async {
        tall(tester);
        final session = await signedIn();
        final gateway = FakeShopGateway()..profile = readyProfile();
        final id = (await gateway.createRequest(
          'k' * 20,
          currency: 'KHR',
          amount: '25000',
        )).id;
        gateway.pay(id);
        final prefs = MerchantPreferences();
        await tester.pumpWidget(
          MerchantApp(
            preferences: prefs,
            session: session,
            shopGateway: gateway,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('today-KHR'))).data,
          '25,000 ៛',
        );
        expect(find.textContaining('Sophea'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('open-wallet-KHR')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('wallet-detail-card')),
          findsOneWidget,
        );
        expect(find.text('QR payment'), findsOneWidget);
        expect(find.text('+25,000 ៛'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        session.dispose();
        prefs.dispose();
      },
    );

    testWidgets('a restricted shop cannot open collection', (tester) async {
      tall(tester);
      final auth = ControlledMerchantAuth();
      final session = MerchantSession(auth);
      final pending = session.signIn();
      auth.approval.complete(
        const MerchantIdentity(
          ownerId: 7,
          shop: MerchantShop(
            id: 'MCH-AB23CD45',
            name: 'Kesor Coffee',
            active: false,
          ),
        ),
      );
      await pending;
      final gateway = FakeShopGateway()
        ..profile = readyProfile(status: 'SUSPENDED');
      final prefs = MerchantPreferences();
      await tester.pumpWidget(
        MerchantApp(preferences: prefs, session: session, shopGateway: gateway),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(NavigationDestination).at(1));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('collect-create')), findsNothing);
      expect(find.textContaining('can’t collect payments'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      prefs.dispose();
    });
  });
}
