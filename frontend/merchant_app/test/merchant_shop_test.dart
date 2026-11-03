import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kesor_auth_handoff/kesor_auth_handoff.dart';
import 'package:merchant_app/app/merchant_app.dart';
import 'package:merchant_app/core/merchant_config.dart';
import 'package:merchant_app/core/merchant_preferences.dart';
import 'package:merchant_app/features/auth/merchant_api_auth.dart';
import 'package:merchant_app/features/auth/merchant_session.dart';
import 'package:merchant_app/features/collect/merchant_collect.dart';
import 'package:merchant_app/features/shop/merchant_shop.dart';
import 'package:merchant_app/features/shop/merchant_shop_api.dart';
import 'package:merchant_app/features/shop/shop_controller.dart';
import 'package:merchant_app/features/shop/shop_form.dart';
import 'package:merchant_app/features/shop/shop_widgets.dart';

import 'merchant_foundation_test.dart' show ControlledMerchantAuth;

const _wallets = [
  ShopWallet(
    accountNumber: '1234567890',
    currency: 'KHR',
    status: 'ACTIVE',
    balance: '0',
  ),
  ShopWallet(
    accountNumber: '2234567890',
    currency: 'USD',
    status: 'ACTIVE',
    balance: '0.00',
  ),
];

ShopProfile readyProfile({
  String name = 'Kesor Coffee',
  int version = 0,
  String status = 'ACTIVE',
  String? logoId,
}) => ShopProfile(
  onboardingState: status == 'ACTIVE' ? 'READY' : 'RESTRICTED',
  ownerName: 'Dara',
  shop: ShopDetails(
    merchantId: 'MCH-AB23CD45',
    storeName: name,
    status: status,
    version: version,
    categoryCode: 'FOOD_DRINK',
    phone: '+85512345678',
    city: 'Phnom Penh',
    address: 'St. 51, Daun Penh',
    logoId: logoId,
  ),
  wallets: _wallets,
);

/// Scriptable shop service. Records every registration key and draft.
class FakeShopGateway implements MerchantShopGateway {
  ShopProfile profile = const ShopProfile(
    onboardingState: 'SHOP_REQUIRED',
    ownerName: 'Dara',
  );
  final registrations = <(String, ShopDraft)>[];
  final updates = <(int, Map<String, Object?>)>[];
  ShopFailure? nextRegister, nextUpdate, nextLoad;
  Completer<void>? registerGate;
  int loads = 0, uploads = 0;

  // ---- collection (M5/M6) ----
  List<ShopReceipt> recent = const [];
  final requests = <String, PaymentRequest>{};
  final createKeys = <String>[];
  ShopFailure? nextCreate, nextStatus;
  DateTime serverNow = DateTime.utc(2026, 11, 3, 3);
  int statusChecks = 0, cancels = 0;

  @override
  Future<ShopDashboard> dashboard() async {
    final profile = await load();
    return ShopDashboard(
      profile: profile,
      businessDate: '2026-11-03',
      today: [
        CurrencyTotal(
          'KHR',
          recent.where((r) => r.currency == 'KHR').length,
          recent.isEmpty ? '0' : '25000',
        ),
        CurrencyTotal(
          'USD',
          recent.where((r) => r.currency == 'USD').length,
          '0.00',
        ),
      ],
      recent: recent,
    );
  }

  @override
  Future<WalletPage> wallet(String accountNumber, {int page = 0}) async =>
      WalletPage(
        profile.wallets.firstWhere((w) => w.accountNumber == accountNumber),
        [
          for (final r in recent)
            WalletActivity(
              reference: r.reference,
              kind: 'QR_PAYMENT',
              incoming: true,
              amount: r.amount,
              currency: r.currency,
              payerName: r.payerName,
              payerAccount: r.payerAccount,
              createdAt: r.paidAt,
            ),
        ],
        page,
        false,
      );

  @override
  Future<ShopQr> shopQr(String currency) async => ShopQr(
    qrString: '00020101021129${currency}static',
    currency: currency,
    accountNumber: currency == 'KHR' ? '1234567890' : '2234567890',
    storeName: profile.shop?.storeName ?? 'Shop',
  );

  PaymentRequest _make(
    String id,
    String currency,
    String amount,
    RequestStatus status, {
    ShopReceipt? receipt,
    String? order,
  }) => PaymentRequest(
    id: id,
    reference: 'PRABCDEFGH23',
    status: status,
    currency: currency,
    amount: amount,
    orderReference: order,
    qrString: status == RequestStatus.waiting ? '000201010212$id' : null,
    expiresAt: serverNow.add(const Duration(minutes: 5)),
    serverTime: serverNow,
    receipt: receipt,
  );

  @override
  Future<PaymentRequest> createRequest(
    String key, {
    required String currency,
    required String amount,
    String? orderReference,
  }) async {
    createKeys.add(key);
    final failure = nextCreate;
    nextCreate = null;
    final id =
        '00000000-0000-4000-8000-${createKeys.length.toString().padLeft(12, '0')}';
    final made = _make(
      id,
      currency,
      amount,
      RequestStatus.waiting,
      order: orderReference,
    );
    requests[id] = made;
    if (failure != null) throw failure;
    return made;
  }

  @override
  Future<PaymentRequest> requestStatus(String id) async {
    statusChecks++;
    final failure = nextStatus;
    nextStatus = null;
    if (failure != null) throw failure;
    final found = requests[id];
    if (found == null) {
      throw const ShopFailure('RESOURCE_NOT_FOUND', status: 404);
    }
    return found;
  }

  @override
  Future<PaymentRequest> cancelRequest(String id) async {
    cancels++;
    final found = requests[id]!;
    if (found.status != RequestStatus.waiting) return found;
    return requests[id] = _make(
      id,
      found.currency,
      found.amount,
      RequestStatus.cancelled,
    );
  }

  /// Simulates a customer paying a waiting request on the server.
  void pay(String id) {
    final found = requests[id]!;
    final receipt = ShopReceipt(
      reference: 'TXN-0001',
      currency: found.currency,
      amount: found.amount,
      paidCurrency: 'USD',
      paidAmount: '6.25',
      payerName: 'Sophea',
      payerAccount: '•••• 4321',
      paidAt: serverNow,
      requestReference: found.reference,
    );
    requests[id] = _make(
      id,
      found.currency,
      found.amount,
      RequestStatus.paid,
      receipt: receipt,
    );
    recent = [receipt, ...recent];
  }

  @override
  Future<ShopProfile> load() async {
    loads++;
    final failure = nextLoad;
    nextLoad = null;
    if (failure != null) throw failure;
    return profile;
  }

  @override
  Future<ShopProfile> register(String key, ShopDraft draft) async {
    registrations.add((key, draft));
    await registerGate?.future;
    final failure = nextRegister;
    nextRegister = null;
    if (failure != null) {
      // An uncertain failure may still have created the shop server-side.
      if (failure.uncertain) profile = readyProfile(name: draft.storeName);
      throw failure;
    }
    return profile = readyProfile(name: draft.storeName, logoId: draft.logoId);
  }

  @override
  Future<ShopProfile> update(int version, Map<String, Object?> changes) async {
    updates.add((version, changes));
    final failure = nextUpdate;
    nextUpdate = null;
    if (failure != null) {
      if (failure.code == 'MERCHANT_PROFILE_CONFLICT') {
        profile = readyProfile(name: 'Changed Elsewhere', version: version + 1);
      }
      throw failure;
    }
    return profile = readyProfile(
      name: changes['storeName'] as String? ?? profile.shop!.storeName,
      version: version + 1,
    );
  }

  @override
  Future<String> uploadLogo(Uint8List bytes, String filename) async {
    uploads++;
    return '00000000-0000-4000-8000-00000000000$uploads';
  }

  @override
  Future<Uint8List?> logo() async => null;
}

const draft = ShopDraft(
  storeName: 'Kesor Coffee',
  categoryCode: 'FOOD_DRINK',
  phone: '012 345 678',
  city: 'Phnom Penh',
  address: 'St. 51, Daun Penh',
);

void main() {
  group('shop controller', () {
    test(
      'saves the intent before sending and clears it after success',
      () async {
        final gateway = FakeShopGateway();
        final store = MemoryHandoffStore();
        final shop = ShopController(gateway, store, ownerId: 7);
        gateway.registerGate = Completer();
        final sending = shop.register(draft);
        await Future<void>.delayed(Duration.zero);
        final saved = jsonDecode(store.values['registration-7']!) as Map;
        expect(saved['key'], gateway.registrations.single.$1);
        expect(saved['draft']['storeName'], 'Kesor Coffee');
        gateway.registerGate!.complete();
        expect(await sending, isTrue);
        expect(store.values, isEmpty);
        expect(shop.pending, isNull);
        expect(shop.shop!.merchantId, 'MCH-AB23CD45');
        expect(shop.profile!.wallets.map((w) => w.currency), ['KHR', 'USD']);
        shop.dispose();
      },
    );

    test('an uncertain result keeps the same key and draft for an explicit retry', () async {
      final gateway = FakeShopGateway()
        ..nextRegister = const ShopFailure('TIMEOUT');
      final store = MemoryHandoffStore();
      final shop = ShopController(gateway, store, ownerId: 7);
      expect(await shop.register(draft), isFalse);
      expect(shop.notice, ShopNotice.uncertain);
      expect(shop.pending, isNotNull);
      expect(gateway.registrations, hasLength(1));

      // A restarted app restores the intent; different form values are ignored.
      final restarted = ShopController(gateway, store, ownerId: 7);
      gateway.profile = const ShopProfile(
        onboardingState: 'SHOP_REQUIRED',
        ownerName: 'Dara',
      );
      await restarted.initialize();
      expect(restarted.pending!.key, gateway.registrations.first.$1);
      const edited = ShopDraft(
        storeName: 'Other',
        categoryCode: 'RETAIL',
        phone: '099999999',
        city: 'Kep',
        address: 'Elsewhere',
      );
      expect(await restarted.register(edited), isTrue);
      expect(gateway.registrations, hasLength(2));
      expect(gateway.registrations[1].$1, gateway.registrations[0].$1);
      expect(gateway.registrations[1].$2.storeName, 'Kesor Coffee');
      expect(store.values, isEmpty);
      shop.dispose();
      restarted.dispose();
    });

    test('a loaded shop clears a stale saved intent', () async {
      final gateway = FakeShopGateway()..profile = readyProfile();
      final store = MemoryHandoffStore()
        ..values['registration-7'] = jsonEncode({
          'key': 'k' * 43,
          'draft': draft.toJson(),
        });
      final shop = ShopController(gateway, store, ownerId: 7);
      await shop.initialize();
      expect(shop.pending, isNull);
      expect(store.values, isEmpty);
      shop.dispose();
    });

    test('saved intents are scoped to their owner', () async {
      final store = MemoryHandoffStore()
        ..values['registration-7'] = jsonEncode({
          'key': 'k' * 43,
          'draft': draft.toJson(),
        });
      final other = ShopController(FakeShopGateway(), store, ownerId: 8);
      await other.initialize();
      expect(other.pending, isNull);
      expect(store.values.keys, ['registration-7']);
      other.dispose();
    });

    test(
      'rejections clear the intent; an existing shop reloads instead',
      () async {
        final gateway = FakeShopGateway()
          ..nextRegister = const ShopFailure(
            'MERCHANT_PHONE_INVALID',
            status: 400,
          );
        final store = MemoryHandoffStore();
        final shop = ShopController(gateway, store, ownerId: 7);
        expect(await shop.register(draft), isFalse);
        expect(shop.pending, isNull);
        expect(store.values, isEmpty);
        expect(shop.failure!.code, 'MERCHANT_PHONE_INVALID');

        gateway
          ..profile = readyProfile()
          ..nextRegister = const ShopFailure(
            'MERCHANT_ALREADY_REGISTERED',
            status: 409,
          );
        expect(await shop.register(draft), isFalse);
        await Future<void>.delayed(Duration.zero);
        expect(shop.shop, isNotNull);
        shop.dispose();
      },
    );

    test(
      'profile edits send the last-read version and reload after a conflict',
      () async {
        final gateway = FakeShopGateway()..profile = readyProfile(version: 3);
        final shop = ShopController(gateway, MemoryHandoffStore(), ownerId: 7);
        await shop.initialize();
        expect(await shop.update({'storeName': 'Lotus'}), isTrue);
        expect(gateway.updates.single.$1, 3);
        expect(shop.shop!.version, 4);
        gateway.nextUpdate = const ShopFailure(
          'MERCHANT_PROFILE_CONFLICT',
          status: 409,
        );
        expect(await shop.update({'city': 'Kep'}), isFalse);
        await Future<void>.delayed(Duration.zero);
        expect(shop.notice, ShopNotice.conflict);
        expect(shop.shop!.storeName, 'Changed Elsewhere');
        shop.dispose();
      },
    );

    test('an expired session is reported to the app', () async {
      var expired = 0;
      final gateway = FakeShopGateway()
        ..nextLoad = const ShopFailure('SESSION_INVALID', status: 401);
      final shop = ShopController(
        gateway,
        MemoryHandoffStore(),
        ownerId: 7,
        onExpired: () => expired++,
      );
      await shop.initialize();
      expect(expired, 1);
      shop.dispose();
    });
  });

  group('shop API', () {
    final config = MerchantConfig(
      apiBaseUrl: 'http://localhost:8080/api/v1',
      environment: 'dev',
    );
    Map<String, dynamic> profileJson() => {
      'onboardingState': 'READY',
      'owner': {'id': 7, 'displayName': 'Dara'},
      'shop': {
        'merchantId': 'MCH-AB23CD45',
        'storeName': 'Kesor Coffee',
        'categoryCode': 'FOOD_DRINK',
        'phone': '+85512345678',
        'city': 'Phnom Penh',
        'address': 'St. 51',
        'description': null,
        'status': 'ACTIVE',
        'logoId': null,
        'version': 0,
      },
      'wallets': [
        {
          'accountNumber': '1234567890',
          'category': 'MERCHANT',
          'merchantId': 'MCH-AB23CD45',
          'currency': 'KHR',
          'status': 'ACTIVE',
          'balance': '0',
        },
      ],
    };

    test('registration carries the key, token and exact body', () async {
      late http.Request seen;
      final api = MerchantShopApi(
        config,
        _StaticAccess(),
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({'success': true, 'data': profileJson()}),
            201,
          );
        }),
      );
      final profile = await api.register('key-1234567890abcdef', draft);
      expect(seen.url.path, '/api/v1/merchants/me/registration');
      expect(seen.headers['Idempotency-Key'], 'key-1234567890abcdef');
      expect(seen.headers['Authorization'], 'Bearer access-token');
      final body = jsonDecode(seen.body) as Map;
      expect(body.keys, isNot(contains('ownerUserId')));
      expect(body['categoryCode'], 'FOOD_DRINK');
      expect(profile.shop!.merchantId, 'MCH-AB23CD45');
      expect(profile.wallets.single.balance, '0');
    });

    test('server errors and lost responses are uncertain', () async {
      for (final response in [
        http.Response('{"success":false,"error":"INTERNAL_ERROR"}', 500),
        http.Response('<html>proxy</html>', 502),
      ]) {
        final api = MerchantShopApi(
          config,
          _StaticAccess(),
          client: MockClient((_) async => response),
        );
        await expectLater(
          api.register('key-1234567890abcdef', draft),
          throwsA(
            isA<ShopFailure>().having((f) => f.uncertain, 'uncertain', true),
          ),
        );
      }
      final rejected = MerchantShopApi(
        config,
        _StaticAccess(),
        client: MockClient(
          (_) async => http.Response(
            '{"success":false,"error":"MERCHANT_PHONE_INVALID"}',
            400,
          ),
        ),
      );
      await expectLater(
        rejected.register('key-1234567890abcdef', draft),
        throwsA(
          isA<ShopFailure>()
              .having((f) => f.uncertain, 'uncertain', false)
              .having((f) => f.code, 'code', 'MERCHANT_PHONE_INVALID'),
        ),
      );
    });

    test('logo upload sends one multipart image part named logo', () async {
      late http.BaseRequest seen;
      String body = '';
      final api = MerchantShopApi(
        config,
        _StaticAccess(),
        client: MockClient.streaming((request, stream) async {
          seen = request;
          body = latin1.decode(await stream.toBytes());
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                jsonEncode({
                  'success': true,
                  'data': {'logoId': 'abc', 'width': 1, 'height': 1},
                }),
              ),
            ),
            201,
          );
        }),
      );
      expect(await api.uploadLogo(Uint8List.fromList([1, 2]), 'Me.PNG'), 'abc');
      expect(seen.headers['Content-Type'], startsWith('multipart/form-data'));
      expect(body, contains('name="logo"; filename="logo.png"'));
      expect(body, isNot(contains('Me.PNG')));
    });
  });

  test(
    'access tokens are reused while fresh and rotated once near expiry',
    () async {
      var refreshes = 0;
      var now = DateTime.utc(2026, 11, 3, 10);
      final store = MemoryHandoffStore()
        ..values['auth'] = jsonEncode({
          'tokens': {
            'access': 'old-access',
            'refresh': 'old-refresh',
            'until': now.add(const Duration(minutes: 5)).toIso8601String(),
          },
        });
      final config = MerchantConfig(
        apiBaseUrl: 'http://localhost:8080/api/v1',
        environment: 'dev',
      );
      final auth = MerchantApiAuth(
        config,
        store: store,
        clock: () => now,
        api: HandoffApi(
          config.apiBaseUrl,
          client: MockClient((request) async {
            expect(request.url.path, '/api/v1/merchant-auth/refresh');
            refreshes++;
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {
                  'accessToken': 'new-access',
                  'refreshToken': 'new-refresh',
                  'expiresInMs': 300000,
                },
              }),
              200,
            );
          }),
        ),
      );
      expect(await auth.accessToken(), 'old-access');
      expect(refreshes, 0);
      now = now.add(const Duration(minutes: 5));
      final both = await Future.wait([auth.accessToken(), auth.accessToken()]);
      expect(both, ['new-access', 'new-access']);
      expect(refreshes, 1);
    },
  );

  test('amounts keep exact server decimals', () {
    expect(shopAmount('0', 'KHR'), '0 ៛');
    expect(shopAmount('1250000', 'KHR'), '1,250,000 ៛');
    expect(shopAmount('0.00', 'USD'), r'$0.00');
    expect(shopAmount('1234.5', 'USD'), r'$1,234.50');
  });

  group('screens', () {
    Future<void> reveal(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
    }

    Future<(MerchantSession, ControlledMerchantAuth)> signedIn({
      MerchantShop? shop,
    }) async {
      final auth = ControlledMerchantAuth();
      final session = MerchantSession(auth);
      final pending = session.signIn();
      auth.approval.complete(MerchantIdentity(ownerId: 7, shop: shop));
      await pending;
      return (session, auth);
    }

    Future<void> fill(WidgetTester tester) async {
      await tester.enterText(
        find.byKey(const ValueKey('shop-name')),
        'Kesor Coffee',
      );
      await tester.tap(find.byKey(const ValueKey('shop-category-null')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Food & drinks').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('shop-phone')),
        '012 345 678',
      );
      await reveal(tester, find.byKey(const ValueKey('shop-city-null')));
      await tester.tap(find.byKey(const ValueKey('shop-city-null')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Phnom Penh').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('shop-address')),
        'St. 51, Daun Penh',
      );
    }

    testWidgets('registration validates, stages a logo and opens the shop', (
      tester,
    ) async {
      // A tall viewport keeps the whole form built; scrolling is covered by visual QA.
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(480, 2600);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (session, _) = await signedIn();
      final gateway = FakeShopGateway();
      final prefs = MerchantPreferences();
      await tester.pumpWidget(
        MerchantApp(
          preferences: prefs,
          session: session,
          shopGateway: gateway,
          pickLogo: () async =>
              PickedLogo(Uint8List.fromList(_png), 'logo.png'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Register your shop'), findsOneWidget);
      await reveal(tester, find.byKey(const ValueKey('register-shop-submit')));
      await tester.tap(find.byKey(const ValueKey('register-shop-submit')));
      await tester.pumpAndSettle();
      expect(gateway.registrations, isEmpty);
      expect(find.text('Required'), findsWidgets);

      await reveal(tester, find.byKey(const ValueKey('shop-logo-pick')));
      await tester.tap(find.byKey(const ValueKey('shop-logo-pick')));
      await tester.pumpAndSettle();
      expect(gateway.uploads, 1);
      await fill(tester);
      await reveal(tester, find.byKey(const ValueKey('register-shop-submit')));
      await tester.tap(find.byKey(const ValueKey('register-shop-submit')));
      await tester.pumpAndSettle();
      expect(gateway.registrations, hasLength(1));
      final sent = gateway.registrations.single.$2;
      expect(sent.categoryCode, 'FOOD_DRINK');
      expect(sent.logoId, isNotNull);

      // Registration success revalidates the identity: the Home shell opens.
      session.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      prefs.dispose();
    });

    testWidgets('an uncertain registration locks the form for a status check', (
      tester,
    ) async {
      // A tall viewport keeps the whole form built; scrolling is covered by visual QA.
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(480, 2600);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (session, _) = await signedIn();
      final gateway = FakeShopGateway()
        ..nextRegister = const ShopFailure('OFFLINE');
      final prefs = MerchantPreferences();
      await tester.pumpWidget(
        MerchantApp(preferences: prefs, session: session, shopGateway: gateway),
      );
      await tester.pumpAndSettle();
      await fill(tester);
      await reveal(tester, find.byKey(const ValueKey('register-shop-submit')));
      await tester.tap(find.byKey(const ValueKey('register-shop-submit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('couldn’t confirm'), findsOneWidget);
      expect(find.text('Check registration status'), findsOneWidget);
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('shop-name')),
          matching: find.byType(TextField),
        ),
      );
      expect(field.enabled, isFalse);
      await reveal(tester, find.byKey(const ValueKey('register-shop-submit')));
      await tester.tap(find.byKey(const ValueKey('register-shop-submit')));
      await tester.pumpAndSettle();
      expect(gateway.registrations, hasLength(2));
      expect(gateway.registrations[1].$1, gateway.registrations[0].$1);
      session.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      prefs.dispose();
    });

    testWidgets(
      'home shows the shop, both zero wallets and edits the profile',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(480, 2600);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final (session, _) = await signedIn(
          shop: const MerchantShop(id: 'MCH-AB23CD45', name: 'Kesor Coffee'),
        );
        final gateway = FakeShopGateway()..profile = readyProfile(version: 2);
        final prefs = MerchantPreferences();
        await tester.pumpWidget(
          MerchantApp(
            preferences: prefs,
            session: session,
            shopGateway: gateway,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Kesor Coffee'), findsOneWidget);
        expect(find.text('MCH-AB23CD45'), findsOneWidget);
        // Wallet balances and today's collections are shown separately.
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('wallet-balance-KHR')))
              .data,
          '0 ៛',
        );
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('today-KHR'))).data,
          '0 ៛',
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('wallet-balance-USD')))
              .data,
          r'$0.00',
        );
        expect(find.text('1234567890'), findsOneWidget);
        expect(find.text('Hello, Dara'), findsOneWidget);

        await tester.tap(find.text('Edit shop'));
        await tester.pumpAndSettle();
        expect(find.text('Shop profile'), findsOneWidget);
        final save = find.byKey(const ValueKey('save-shop-profile'));
        await reveal(tester, save);
        expect(tester.widget<FilledButton>(save).onPressed, isNull);
        await tester.enterText(
          find.byKey(const ValueKey('shop-name')),
          'Lotus Tea',
        );
        await tester.pumpAndSettle();
        await reveal(tester, save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(gateway.updates.single.$1, 2);
        expect(gateway.updates.single.$2, {'storeName': 'Lotus Tea'});
        expect(find.text('Lotus Tea'), findsOneWidget);
        session.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        prefs.dispose();
      },
    );
  });
}

class _StaticAccess implements MerchantAccess {
  @override
  Future<String> accessToken() async => 'access-token';
}

/// 1x1 transparent PNG.
const _png = [
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  120,
  156,
  99,
  248,
  15,
  4,
  0,
  9,
  251,
  3,
  253,
  99,
  38,
  197,
  143,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
];
