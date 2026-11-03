import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kesor_auth_handoff/kesor_auth_handoff.dart';
import 'package:kesor_design_system/kesor_design_system.dart';
import 'package:merchant_app/app/merchant_app.dart';
import 'package:merchant_app/core/merchant_preferences.dart';
import 'package:merchant_app/features/auth/merchant_session.dart';
import 'package:merchant_app/features/collect/collect_controller.dart';
import 'package:merchant_app/features/collect/merchant_collect.dart';
import 'package:merchant_app/features/feed/payment_banner.dart';
import 'package:merchant_app/features/feed/payment_feed_controller.dart';
import 'package:merchant_app/features/shop/merchant_shop.dart';

import 'merchant_foundation_test.dart' show ControlledMerchantAuth;
import 'merchant_shop_test.dart' show FakeShopGateway, readyProfile;
import 'merchant_sales_test.dart' show receiptFixture;

class _Effects implements AlertEffects {
  int chimes = 0, vibrations = 0;
  @override
  void chime() => chimes++;
  @override
  void vibrate() => vibrations++;
}

/// Lets a test hold a dashboard response while the feed is stopped.
class _GatedGateway extends FakeShopGateway {
  Completer<void>? gate;
  @override
  Future<ShopDashboard> dashboard() async {
    final held = gate;
    final result = await super.dashboard();
    if (held != null) await held.future;
    return result;
  }
}

PaymentFeedController _feedFor(
  FakeShopGateway gateway,
  _Effects effects, {
  bool sound = true,
  bool vibration = true,
  void Function(List<ShopReceipt>)? onNew,
  VoidCallback? onExpired,
}) => PaymentFeedController(
  gateway,
  effects: effects,
  soundEnabled: () => sound,
  vibrationEnabled: () => vibration,
  onNewPayments: onNew,
  onExpired: onExpired,
);

void main() {
  group('payment feed', () {
    test('the first load records history without alerting', () async {
      final gateway = FakeShopGateway()
        ..profile = readyProfile()
        ..recent = [receiptFixture('TXN-OLD')];
      final effects = _Effects();
      final feed = _feedFor(gateway, effects)..running = true;
      await Future<void>.delayed(Duration.zero);
      expect(gateway.loads, 1);
      expect(feed.banner, isNull);
      expect(effects.chimes + effects.vibrations, 0);
      feed.dispose();
    });

    test(
      'a new reference alerts exactly once and refreshes the shop',
      () async {
        final gateway = FakeShopGateway()..profile = readyProfile();
        final effects = _Effects();
        final seen = <List<ShopReceipt>>[];
        final feed = _feedFor(gateway, effects, onNew: seen.add)
          ..running = true;
        await Future<void>.delayed(Duration.zero);
        gateway.recent = [receiptFixture('TXN-NEW')];
        await feed.poll();
        expect(feed.banner!.payments.single.reference, 'TXN-NEW');
        expect(effects.chimes, 1);
        expect(effects.vibrations, 1);
        expect(seen, hasLength(1));
        final first = feed.banner!.sequence;

        await feed.poll();
        expect(
          effects.chimes,
          1,
          reason: 'the same payment never alerts twice',
        );
        expect(feed.banner!.sequence, first);

        gateway.recent = [
          receiptFixture('TXN-NEWER'),
          receiptFixture('TXN-NEW'),
        ];
        await feed.poll();
        expect(feed.banner!.payments.map((r) => r.reference), ['TXN-NEWER']);
        expect(feed.banner!.sequence, greaterThan(first));
        feed.dispose();
      },
    );

    test('sound and vibration follow the owner settings', () async {
      final gateway = FakeShopGateway()..profile = readyProfile();
      final effects = _Effects();
      final feed = _feedFor(gateway, effects, sound: false)..running = true;
      await Future<void>.delayed(Duration.zero);
      gateway.recent = [receiptFixture('TXN-NEW')];
      await feed.poll();
      expect(feed.banner, isNotNull, reason: 'the banner always shows');
      expect(effects.chimes, 0);
      expect(effects.vibrations, 1);
      feed.dispose();
    });

    test('a payment the Collect screen confirmed never alerts again', () async {
      final gateway = FakeShopGateway()..profile = readyProfile();
      final effects = _Effects();
      late final PaymentFeedController feed;
      final collect = CollectController(
        gateway,
        MemoryHandoffStore(),
        ownerId: 7,
        pollEvery: const Duration(milliseconds: 5),
        onReceipt: (receipt) => feed.markSeen(receipt.reference),
      );
      feed = _feedFor(gateway, effects)..running = true;
      await Future<void>.delayed(Duration.zero);
      expect(await collect.create(currency: 'KHR', amount: '25000'), isTrue);
      gateway.pay(collect.request!.id);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(collect.request!.status, RequestStatus.paid);
      expect(gateway.recent, isNotEmpty);
      await feed.poll();
      expect(feed.banner, isNull);
      expect(effects.chimes, 0);
      collect.dispose();
      feed.dispose();
    });

    test(
      'stopping drops a poll in flight; resuming reports what arrived',
      () async {
        final gateway = _GatedGateway()..profile = readyProfile();
        final effects = _Effects();
        final feed = _feedFor(gateway, effects)..running = true;
        await Future<void>.delayed(Duration.zero);
        gateway
          ..recent = [receiptFixture('TXN-AWAY')]
          ..gate = Completer<void>();
        final inFlight = feed.poll();
        await Future<void>.delayed(Duration.zero);
        feed.running = false;
        gateway.gate!.complete();
        await inFlight;
        expect(feed.banner, isNull, reason: 'a stopped feed never alerts');

        gateway.gate = null;
        feed.running = true;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(feed.banner!.payments.single.reference, 'TXN-AWAY');
        feed.dispose();
      },
    );

    test('a quick stop and restart during a poll still resumes polling and reports the payment', () async {
      final gateway = _GatedGateway()..profile = readyProfile();
      final effects = _Effects();
      final feed = _feedFor(gateway, effects)..running = true;
      await Future<void>.delayed(Duration.zero);
      gateway
        ..recent = [receiptFixture('TXN-SHADE')]
        ..gate = Completer<void>();
      final inFlight = feed.poll();
      await Future<void>.delayed(Duration.zero);
      // The notification shade: inactive, then resumed, before the poll returns.
      feed.running = false;
      feed.running = true;
      final loadsBefore = gateway.loads;
      gateway.gate!.complete();
      gateway.gate = null;
      await inFlight;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        gateway.loads,
        greaterThan(loadsBefore),
        reason: 'the feed must not go silent',
      );
      expect(feed.banner!.payments.single.reference, 'TXN-SHADE');
      expect(effects.chimes, 1);
      feed.dispose();
    });

    test(
      'failures back off to the slow interval and success restores it',
      () async {
        final gateway = FakeShopGateway()..profile = readyProfile();
        final feed = _feedFor(gateway, _Effects())..running = true;
        await Future<void>.delayed(Duration.zero);
        expect(feed.delay, const Duration(seconds: 10));
        for (var i = 0; i < 3; i++) {
          gateway.nextLoad = const ShopFailure('OFFLINE');
          await feed.poll();
        }
        expect(feed.failures, 3);
        expect(feed.delay, const Duration(seconds: 30));
        await feed.poll();
        expect(feed.failures, 0);
        expect(feed.delay, const Duration(seconds: 10));
        feed.dispose();
      },
    );

    test('an expired session stops the feed and reports it once', () async {
      final gateway = FakeShopGateway()..profile = readyProfile();
      var expired = 0;
      final feed = _feedFor(gateway, _Effects(), onExpired: () => expired++);
      gateway.nextLoad = const ShopFailure('SESSION_INVALID', status: 401);
      feed.running = true;
      await Future<void>.delayed(Duration.zero);
      expect(expired, 1);
      expect(feed.running, isFalse);
      feed.dispose();
    });

    test('a disposed feed never polls again', () async {
      final gateway = FakeShopGateway()..profile = readyProfile();
      final feed = PaymentFeedController(
        gateway,
        effects: _Effects(),
        interval: const Duration(milliseconds: 5),
      )..running = true;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      feed.dispose();
      final loads = gateway.loads;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(gateway.loads, loads);
    });

    test('a new owner starts with no memory of the previous one', () async {
      final gateway = FakeShopGateway()
        ..profile = readyProfile()
        ..recent = [receiptFixture('TXN-ONE')];
      final first = _feedFor(gateway, _Effects())..running = true;
      await Future<void>.delayed(Duration.zero);
      first.dispose();
      final effects = _Effects();
      final second = _feedFor(gateway, effects)..running = true;
      await Future<void>.delayed(Duration.zero);
      expect(second.banner, isNull, reason: 'the first load only seeds');
      expect(effects.chimes, 0);
      second.dispose();
    });

    testWidgets('polling repeats on the interval while running', (
      tester,
    ) async {
      final gateway = FakeShopGateway()..profile = readyProfile();
      final feed = _feedFor(gateway, _Effects())..running = true;
      await tester.pump();
      expect(gateway.loads, 1);
      await tester.pump(const Duration(seconds: 10));
      expect(gateway.loads, 2);
      feed.running = false;
      await tester.pump(const Duration(seconds: 30));
      expect(gateway.loads, 2);
      feed.dispose();
    });
  });

  group('payment feed in the app', () {
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

    testWidgets(
      'alerts while open, stops while covered, and sign-out forgets the shop',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(480, 2600);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final session = await signedIn();
        final gateway = FakeShopGateway()..profile = readyProfile();
        final effects = _Effects();
        final prefs = MerchantPreferences();
        await tester.pumpWidget(
          MerchantApp(
            preferences: prefs,
            session: session,
            shopGateway: gateway,
            alertEffects: effects,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byKey(const ValueKey('payment-banner-text')), findsNothing);

        // A payment to the reusable shop QR has no request to watch.
        gateway.recent = [receiptFixture('TXN-SHOP-QR')];
        await tester.pump(const Duration(seconds: 10));
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('payment-banner-text')))
              .data,
          '+25,000 ៛ from Sophea',
        );
        expect(effects.chimes, 1);
        expect(effects.vibrations, 1);

        // Covered: the feed stops, so a payment waits until the app returns.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        final loadsWhenCovered = gateway.loads;
        gateway.recent = [receiptFixture('TXN-AWAY'), ...gateway.recent];
        await tester.pump(const Duration(seconds: 40));
        expect(gateway.loads, loadsWhenCovered);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(effects.chimes, 2);

        await tester.pumpWidget(const SizedBox.shrink());
        session.dispose();
        prefs.dispose();
      },
    );
  });

  group('payment alerts UI', () {
    testWidgets('the banner names the payer and closes itself', (tester) async {
      final gateway = FakeShopGateway()..profile = readyProfile();
      final feed = _feedFor(gateway, _Effects())..running = true;
      await tester.pump();
      gateway.recent = [receiptFixture('TXN-NEW')];
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: PaymentBannerHost(
            controller: feed,
            onOpen: () => opened++,
            visibleFor: const Duration(seconds: 2),
            child: const Scaffold(body: Text('underneath')),
          ),
        ),
      );
      await feed.poll();
      await tester.pump();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('payment-banner-text')))
            .data,
        '+25,000 ៛ from Sophea',
      );
      expect(find.text('underneath'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const ValueKey('payment-banner-text')), findsNothing);

      gateway.recent = [receiptFixture('TXN-NEWER'), ...gateway.recent];
      await feed.poll();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('payment-banner-text')));
      await tester.pump();
      expect(opened, 1);
      expect(feed.banner, isNull);
      feed.running = false;
      feed.dispose();
    });

    testWidgets('several payments are summarized', (tester) async {
      final gateway = FakeShopGateway()..profile = readyProfile();
      final feed = _feedFor(gateway, _Effects())..running = true;
      await tester.pump();
      gateway.recent = [receiptFixture('A'), receiptFixture('B')];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: PaymentBannerHost(
            controller: feed,
            onOpen: () {},
            child: const Scaffold(),
          ),
        ),
      );
      await feed.poll();
      await tester.pump();
      expect(find.text('2 new payments received'), findsOneWidget);
      feed.running = false;
      feed.dispose();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('alert toggles persist on this device and note the limit', (
      tester,
    ) async {
      final store = MemoryMerchantPreferenceStore();
      final prefs = MerchantPreferences(store: store);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: Scaffold(body: PaymentAlertSettings(preferences: prefs)),
        ),
      );
      expect(
        find.textContaining('Background notifications are coming later'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('alert-sound')));
      await tester.pump();
      expect(prefs.alertSound, isFalse);
      expect(prefs.alertVibration, isTrue);
      await prefs.saved;
      final reloaded = MerchantPreferences(store: store);
      await reloaded.load();
      expect(reloaded.alertSound, isFalse);
      expect(reloaded.alertVibration, isTrue);
    });
  });
}
