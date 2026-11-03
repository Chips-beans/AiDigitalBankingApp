import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_app/app/merchant_app.dart';
import 'package:merchant_app/core/merchant_config.dart';
import 'package:merchant_app/core/merchant_preferences.dart';
import 'package:merchant_app/features/auth/merchant_session.dart';

class ControlledMerchantAuth implements MerchantAuthGateway {
  final approval = Completer<MerchantIdentity>();
  int starts = 0, cancellations = 0, signOuts = 0;
  @override
  Future<MerchantIdentity> authorize() {
    starts++;
    return approval.future;
  }

  @override
  Future<void> cancel() async {
    cancellations++;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
  }
}

void main() {
  test(
    'configuration refuses unsafe production and credential-bearing origins',
    () {
      for (final url in [
        'http://bank.test/api/v1',
        'https://u:p@bank.test/api/v1',
        'https://bank.test/api/v1?token=secret',
        'https://bank.test/other',
      ]) {
        expect(
          () => MerchantConfig(apiBaseUrl: url, environment: 'prod'),
          throwsArgumentError,
        );
      }
      final config = MerchantConfig(
        apiBaseUrl: 'https://bank.test/api/v1',
        environment: 'prod',
      );
      expect(config.storageNamespace, startsWith('kesor.merchant.v1|'));
      expect(
        config.storageNamespace,
        isNot(
          MerchantConfig(
            apiBaseUrl: 'https://other.test/api/v1',
            environment: 'prod',
          ).storageNamespace,
        ),
      );
      expect(
        MerchantConfig.androidPackage,
        isNot(MerchantConfig.customerPackage),
      );
    },
  );

  test('production scaffold cannot create a local merchant identity', () async {
    final session = MerchantSession(UnavailableMerchantAuth());
    await session.signIn();
    expect(session.phase, MerchantPhase.signedOut);
    expect(session.identity, isNull);
    expect(session.unavailable, isTrue);
    session.dispose();
  });

  test(
    'double taps start one approval; cancellation rejects the late identity',
    () async {
      final auth = ControlledMerchantAuth();
      final session = MerchantSession(auth);
      final pending = session.signIn();
      await session.signIn();
      expect(auth.starts, 1);
      await session.cancel();
      auth.approval.complete(
        const MerchantIdentity(
          ownerId: 1,
          shop: MerchantShop(id: 'shop-a', name: 'Shop A'),
        ),
      );
      await pending;
      expect(session.identity, isNull);
      expect(session.phase, MerchantPhase.signedOut);
      expect(auth.cancellations, 1);
      session.dispose();
    },
  );

  test(
    'a disposed session never publishes a pending approval result',
    () async {
      final auth = ControlledMerchantAuth();
      final session = MerchantSession(auth);
      final pending = session.signIn();
      session.dispose();
      auth.approval.complete(const MerchantIdentity(ownerId: 1));
      await pending;
      expect(session.identity, isNull);
    },
  );

  test(
    'onboarding, active shop and restricted shop route independently',
    () async {
      for (final entry in [
        (const MerchantIdentity(ownerId: 1), MerchantPhase.shopRequired),
        (
          const MerchantIdentity(
            ownerId: 1,
            shop: MerchantShop(id: 'a', name: 'Shop A'),
          ),
          MerchantPhase.ready,
        ),
        (
          const MerchantIdentity(
            ownerId: 1,
            shop: MerchantShop(id: 'a', name: 'Shop A', active: false),
          ),
          MerchantPhase.restricted,
        ),
      ]) {
        final auth = ControlledMerchantAuth();
        final session = MerchantSession(auth);
        final pending = session.signIn();
        auth.approval.complete(entry.$1);
        await pending;
        expect(session.phase, entry.$2);
        await session.signOut();
        expect(session.identity, isNull);
        expect(auth.signOuts, 1);
        session.dispose();
      }
    },
  );

  test(
    'invalid identity and corrupt display preferences fall back safely',
    () async {
      final auth = ControlledMerchantAuth();
      final session = MerchantSession(auth);
      final pending = session.signIn();
      auth.approval.complete(const MerchantIdentity(ownerId: 0));
      await pending;
      expect(session.phase, MerchantPhase.signedOut);
      final store = MemoryMerchantPreferenceStore()..value = 'broken-json';
      final prefs = MerchantPreferences(store: store);
      await prefs.load();
      expect(prefs.locale.languageCode, 'en');
      session.dispose();
      prefs.dispose();
    },
  );

  test(
    'display settings persist in order and unsupported languages are ignored',
    () async {
      final store = MemoryMerchantPreferenceStore();
      final prefs = MerchantPreferences(store: store);
      prefs.setLanguage('km');
      prefs.setTheme(ThemeMode.dark);
      prefs.setLanguage('xx');
      await prefs.saved;
      final restored = MerchantPreferences(store: store);
      await restored.load();
      expect(restored.locale.languageCode, 'km');
      expect(restored.themeMode, ThemeMode.dark);
      prefs.dispose();
      restored.dispose();
    },
  );

  test(
    'typed connectivity failures grant no identity; expiry clears a prior shop',
    () async {
      final offline = ControlledMerchantAuth();
      final rejected = MerchantSession(offline);
      final attempt = rejected.signIn();
      offline.approval.completeError(
        const MerchantAuthFailure(MerchantAuthIssue.offline),
      );
      await attempt;
      expect(rejected.failure, MerchantAuthIssue.offline);
      expect(rejected.identity, isNull);
      rejected.dispose();

      final auth = ControlledMerchantAuth();
      final session = MerchantSession(auth);
      final signed = session.signIn();
      auth.approval.complete(
        const MerchantIdentity(
          ownerId: 1,
          shop: MerchantShop(id: 'a', name: 'Shop A'),
        ),
      );
      await signed;
      session.expire();
      expect(session.phase, MerchantPhase.signedOut);
      expect(session.failure, MerchantAuthIssue.expired);
      expect(session.identity, isNull);
      session.dispose();
    },
  );

  testWidgets(
    'welcome has one customer-app sign-in and never enters local banking',
    (tester) async {
      final session = MerchantSession(UnavailableMerchantAuth());
      final prefs = MerchantPreferences();
      await tester.pumpWidget(
        MerchantApp(preferences: prefs, session: session),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('continue-with-kesor')), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('continue-with-kesor')),
      );
      await tester.tap(find.byKey(const ValueKey('continue-with-kesor')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('merchant-auth-unavailable')),
        findsOneWidget,
      );
      expect(find.byType(NavigationBar), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      prefs.dispose();
    },
  );

  testWidgets(
    'shop name, navigation, missing data and sign-out stay truthful',
    (tester) async {
      final auth = ControlledMerchantAuth();
      final session = MerchantSession(auth);
      final pending = session.signIn();
      auth.approval.complete(
        const MerchantIdentity(
          ownerId: 42,
          shop: MerchantShop(id: 'shop', name: 'Lotus Coffee'),
        ),
      );
      await pending;
      final prefs = MerchantPreferences();
      await tester.pumpWidget(
        MerchantApp(preferences: prefs, session: session),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lotus Coffee'), findsOneWidget);
      // Without the shop service nothing is invented: no wallets or balances.
      expect(
        find.text('Shop details are currently unavailable.'),
        findsOneWidget,
      );
      expect(find.text('200.00'), findsNothing);
      await tester.tap(find.byType(NavigationDestination).at(1));
      await tester.pumpAndSettle();
      expect(find.text('Collection unavailable'), findsOneWidget);
      await tester.tap(find.byType(NavigationDestination).at(2));
      await tester.pumpAndSettle();
      expect(find.text('Sales unavailable'), findsOneWidget);
      await tester.tap(find.byType(NavigationDestination).at(3));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sign out'));
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Lotus Coffee'), findsNothing);
      expect(find.byKey(const ValueKey('continue-with-kesor')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      prefs.dispose();
    },
  );

  testWidgets('inactive lifecycle conceals shop content until resumed', (
    tester,
  ) async {
    final auth = ControlledMerchantAuth();
    final session = MerchantSession(auth);
    final pending = session.signIn();
    auth.approval.complete(
      const MerchantIdentity(
        ownerId: 1,
        shop: MerchantShop(id: 'x', name: 'Private Shop'),
      ),
    );
    await pending;
    final prefs = MerchantPreferences();
    await tester.pumpWidget(MerchantApp(preferences: prefs, session: session));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('Private Shop'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Private Shop'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
    prefs.dispose();
  });
}
