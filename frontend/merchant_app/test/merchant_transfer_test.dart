import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kesor_auth_handoff/kesor_auth_handoff.dart';
import 'package:kesor_design_system/kesor_design_system.dart';
import 'package:merchant_app/app/merchant_app.dart';
import 'package:merchant_app/core/merchant_config.dart';
import 'package:merchant_app/core/merchant_preferences.dart';
import 'package:merchant_app/features/auth/merchant_session.dart';
import 'package:merchant_app/features/feed/payment_feed_controller.dart';
import 'package:merchant_app/features/shop/merchant_shop.dart';
import 'package:merchant_app/features/shop/merchant_shop_api.dart';
import 'package:merchant_app/features/transfer/owner_transfer.dart';
import 'package:merchant_app/features/transfer/owner_transfer_controller.dart';
import 'package:merchant_app/features/transfer/owner_transfer_page.dart';

import 'merchant_foundation_test.dart' show ControlledMerchantAuth;
import 'merchant_shop_test.dart' show FakeShopGateway, readyProfile;

class _Access implements MerchantAccess {
  @override
  Future<String> accessToken() async => 'access-token';
}

class _Silent implements AlertEffects {
  @override
  void chime() {}
  @override
  void vibrate() {}
}

class _Native extends NativeHandoff {
  final opened = <String>[], returned = <String>[];
  String? error;
  @override
  Future<String?> takeTransfer() async =>
      returned.isEmpty ? null : returned.removeAt(0);
  @override
  Future<void> openTransfer(String uri) async {
    if (error != null) throw HandoffFailure(error!);
    opened.add(uri);
  }
}

const khrWallet = ShopWallet(
  accountNumber: '1234567890',
  currency: 'KHR',
  status: 'ACTIVE',
  balance: '100000',
);
const usdWallet = ShopWallet(
  accountNumber: '2234567890',
  currency: 'USD',
  status: 'ACTIVE',
  balance: '50.00',
);

ShopProfile fundedProfile({String status = 'ACTIVE'}) {
  final base = readyProfile(status: status);
  return ShopProfile(
    onboardingState: base.onboardingState,
    ownerName: base.ownerName,
    shop: base.shop,
    wallets: const [khrWallet, usdWallet],
  );
}

OwnerTransferController controllerFor(
  FakeShopGateway gateway,
  MemoryHandoffStore store,
  NativeHandoff native, {
  VoidCallback? onCompleted,
  VoidCallback? onExpired,
}) => OwnerTransferController(
  gateway,
  store,
  ownerId: 7,
  native: native,
  onCompleted: onCompleted,
  onExpired: onExpired,
  pollEvery: const Duration(milliseconds: 10),
);

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  group('owner transfer controller', () {
    test('create keeps the intent, completion refreshes the shop once and clears it', () async {
      final gateway = FakeShopGateway()..profile = fundedProfile();
      final store = MemoryHandoffStore();
      var completed = 0;
      final controller = controllerFor(
        gateway,
        store,
        _Native(),
        onCompleted: () => completed++,
      );
      expect(
        await controller.create(
          sourceAccountNumber: '2234567890',
          amount: '12.50',
        ),
        isTrue,
      );
      final id = controller.transfer!.id;
      expect(controller.waiting, isTrue);
      expect(controller.transfer!.destinationAccount, '•••• 5678');
      expect(store.values['owner-transfer-7'], contains(id));
      expect(store.values['owner-transfer-7'], isNot(contains('handoff')));
      expect(
        controller.remaining,
        lessThanOrEqualTo(const Duration(minutes: 5)),
      );

      gateway.resolveTransfer(id, TransferStatus.completed);
      await settle();
      expect(controller.transfer!.status, TransferStatus.completed);
      expect(controller.transfer!.receiptReference, 'TXN-OWNER-0001');
      expect(completed, 1);
      expect(store.values.containsKey('owner-transfer-7'), isFalse);
      await settle();
      expect(completed, 1);
      controller.dispose();
    });

    test(
      'an uncertain create keeps its key; a rejection or new amount does not',
      () async {
        final gateway = FakeShopGateway()..profile = fundedProfile();
        final controller = controllerFor(
          gateway,
          MemoryHandoffStore(),
          _Native(),
        );
        gateway.nextTransferCreate = const ShopFailure('TIMEOUT');
        expect(
          await controller.create(
            sourceAccountNumber: '2234567890',
            amount: '5.00',
          ),
          isFalse,
        );
        expect(controller.failure!.uncertain, isTrue);
        expect(
          await controller.create(
            sourceAccountNumber: '2234567890',
            amount: '5.00',
          ),
          isTrue,
        );
        expect(gateway.transferKeys[1], gateway.transferKeys[0]);
        await controller.cancel();
        await controller.reset();

        gateway.nextTransferCreate = const ShopFailure(
          'INSUFFICIENT_FUNDS',
          status: 409,
        );
        expect(
          await controller.create(
            sourceAccountNumber: '2234567890',
            amount: '1.00',
          ),
          isFalse,
        );
        expect(
          await controller.create(
            sourceAccountNumber: '2234567890',
            amount: '1.00',
          ),
          isTrue,
        );
        expect(gateway.transferKeys[3], isNot(gateway.transferKeys[2]));
        controller.dispose();
      },
    );

    test(
      'after a restart the transfer resumes and a replay returns a fresh link',
      () async {
        final gateway = FakeShopGateway()..profile = fundedProfile();
        final store = MemoryHandoffStore();
        final first = controllerFor(gateway, store, _Native());
        await first.create(sourceAccountNumber: '1234567890', amount: '25000');
        final id = first.transfer!.id;
        final key = gateway.transferKeys.single;
        first.dispose();

        final native = _Native();
        final second = controllerFor(gateway, store, native);
        await second.resume();
        expect(second.transfer!.id, id);
        expect(
          second.transfer!.approvalUri,
          isNull,
          reason: 'secrets are not stored',
        );
        await second.openApproval();
        expect(
          gateway.transferKeys.last,
          key,
          reason: 'same key replays the intent',
        );
        expect(
          native.opened.single,
          startsWith('$transferApprovalBase?intentId=$id&handoffToken='),
        );
        expect(gateway.transfers, hasLength(1));
        second.dispose();
      },
    );

    test(
      'a cancel that loses to the owner shows the completed transfer',
      () async {
        final gateway = FakeShopGateway()..profile = fundedProfile();
        final controller = controllerFor(
          gateway,
          MemoryHandoffStore(),
          _Native(),
        );
        await controller.create(
          sourceAccountNumber: '2234567890',
          amount: '5.00',
        );
        gateway.resolveTransfer(
          controller.transfer!.id,
          TransferStatus.completed,
        );
        await controller.cancel();
        expect(controller.transfer!.status, TransferStatus.completed);
        controller.dispose();
      },
    );

    test(
      'denied, expired and failed transfers are terminal and never completed',
      () async {
        for (final (status, code) in [
          (TransferStatus.denied, null),
          (TransferStatus.expired, null),
          (TransferStatus.failed, 'INSUFFICIENT_FUNDS'),
        ]) {
          final gateway = FakeShopGateway()..profile = fundedProfile();
          var completed = 0;
          final controller = controllerFor(
            gateway,
            MemoryHandoffStore(),
            _Native(),
            onCompleted: () => completed++,
          );
          await controller.create(
            sourceAccountNumber: '2234567890',
            amount: '5.00',
          );
          gateway.resolveTransfer(
            controller.transfer!.id,
            status,
            failureCode: code,
          );
          await settle();
          expect(controller.transfer!.status, status);
          expect(controller.transfer!.failureCode, code);
          expect(completed, 0);
          controller.dispose();
        }
      },
    );

    test('a return link only prompts a status check and must match the saved state', () async {
      final gateway = FakeShopGateway()..profile = fundedProfile();
      final native = _Native();
      final controller = OwnerTransferController(
        gateway,
        MemoryHandoffStore(),
        ownerId: 7,
        native: native,
        pollEvery: const Duration(hours: 1),
      );
      await controller.create(
        sourceAccountNumber: '2234567890',
        amount: '5.00',
      );
      final id = controller.transfer!.id;
      final before = gateway.transferStatusChecks;
      native.returned.addAll([
        '$transferCallbackBase?intentId=$id&state=${'x' * 43}',
        '$callbackBase?code=${'c' * 43}&state=${'s' * 43}',
        '$transferCallbackBase?intentId=$id&state=${'s' * 43}',
      ]);
      for (var i = 0; i < 3; i++) {
        await controller.refresh();
      }
      expect(native.returned, isEmpty, reason: 'every link is consumed once');
      expect(gateway.transferStatusChecks - before, 3);
      expect(
        controller.transfer!.status,
        TransferStatus.pending,
        reason: 'a link never completes a transfer by itself',
      );
      controller.dispose();
    });

    test('opening Kesor Bank reports a missing or unverified app', () async {
      final gateway = FakeShopGateway()..profile = fundedProfile();
      final native = _Native()..error = 'PEER_MISSING';
      final controller = controllerFor(gateway, MemoryHandoffStore(), native);
      await controller.create(
        sourceAccountNumber: '2234567890',
        amount: '5.00',
      );
      await controller.openApproval();
      expect(controller.failure!.code, 'PEER_MISSING');
      expect(native.opened, isEmpty);
      expect(controller.waiting, isTrue);
      controller.dispose();
    });

    test('an expired session is reported to the app', () async {
      final gateway = FakeShopGateway()..profile = fundedProfile();
      var expired = 0;
      final controller = controllerFor(
        gateway,
        MemoryHandoffStore(),
        _Native(),
        onExpired: () => expired++,
      );
      await controller.create(
        sourceAccountNumber: '2234567890',
        amount: '5.00',
      );
      gateway.nextTransferStatus = const ShopFailure(
        'SESSION_INVALID',
        status: 401,
      );
      await controller.refresh();
      expect(expired, 1);
      controller.dispose();
    });
  });

  group('owner transfer API', () {
    final config = MerchantConfig(
      apiBaseUrl: 'http://localhost:8080/api/v1',
      environment: 'dev',
    );
    const id = '66666666-6666-4666-8666-000000000001';
    Map<String, dynamic> view({
      String status = 'PENDING',
      String? approvalUri,
      String? state,
      Map<String, dynamic>? receipt,
      String destination = '•••• 5678',
    }) => {
      'intentId': id,
      'status': status,
      'sourceAccountNumber': '2234567890',
      'destinationAccount': destination,
      'currency': 'USD',
      'amount': '12.50',
      'createdAt': '2026-11-03T10:00:00+07:00',
      'expiresAt': '2026-11-03T10:05:00+07:00',
      'serverTime': '2026-11-03T10:01:00+07:00',
      'failureCode': null,
      'receipt': receipt,
      'approvalUri': approvalUri,
      'state': state,
    };
    final link = '$transferApprovalBase?intentId=$id&handoffToken=${'h' * 43}';

    MerchantShopApi apiFor(
      Map<String, dynamic> data,
      void Function(http.Request)? seen,
    ) => MerchantShopApi(
      config,
      _Access(),
      client: MockClient((request) async {
        seen?.call(request);
        return http.Response(
          jsonEncode({'success': true, 'data': data}),
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    test(
      'create sends only the source and amount, with the key and token',
      () async {
        late http.Request seen;
        final api = apiFor(
          view(approvalUri: link, state: 's' * 43),
          (r) => seen = r,
        );
        final transfer = await api.createOwnerTransfer(
          'key-1234567890abcdef',
          sourceAccountNumber: '2234567890',
          amount: '12.50',
        );
        expect(seen.method, 'POST');
        expect(seen.url.path, '/api/v1/merchants/me/owner-transfers');
        expect(seen.headers['Idempotency-Key'], 'key-1234567890abcdef');
        expect(seen.headers['Authorization'], 'Bearer access-token');
        expect(jsonDecode(seen.body), {
          'sourceAccountNumber': '2234567890',
          'amount': '12.50',
        });
        expect(transfer.remainingAtFetch, const Duration(minutes: 4));
        expect(transfer.approvalUri, link);
      },
    );

    test('status and cancel use the exact paths and validate the id', () async {
      final seen = <http.Request>[];
      final api = apiFor(
        view(
          status: 'COMPLETED',
          receipt: {
            'reference': 'TXN-1',
            'completedAt': '2026-11-03T10:02:00+07:00',
          },
        ),
        seen.add,
      );
      expect((await api.ownerTransferStatus(id)).receiptReference, 'TXN-1');
      await api.cancelOwnerTransfer(id);
      expect(seen[0].url.path, '/api/v1/merchants/me/owner-transfers/$id');
      expect(
        seen[1].url.path,
        '/api/v1/merchants/me/owner-transfers/$id/cancel',
      );
      await expectLater(
        api.ownerTransferStatus('../wallets'),
        throwsA(isA<ShopFailure>()),
      );
      await expectLater(
        api.createOwnerTransfer(
          'k' * 20,
          sourceAccountNumber: '12/34',
          amount: '1',
        ),
        throwsA(isA<ShopFailure>()),
      );
    });

    test('forged or malformed responses fail closed', () async {
      Future<void> rejects(Map<String, dynamic> data) => expectLater(
        apiFor(data, null).ownerTransferStatus(id),
        throwsA(
          isA<ShopFailure>().having((f) => f.code, 'code', 'INVALID_RESPONSE'),
        ),
      );
      await rejects(view(status: 'SETTLED'));
      await rejects(view(destination: '5678'));
      await rejects(view(destination: '1234567890'));
      // Completed without a receipt, or an approval link without its state (or the reverse).
      await rejects(view(status: 'COMPLETED'));
      await rejects(view(approvalUri: link));
      await rejects(view(state: 's' * 43));
      // A link for another transfer, the sign-in link, or extra parameters is never accepted.
      await rejects(
        view(
          approvalUri: link.replaceFirst(
            id,
            '77777777-7777-4777-8777-777777777777',
          ),
          state: 's' * 43,
        ),
      );
      await rejects(
        view(
          approvalUri: '$approvalBase?attemptId=$id&handoffToken=${'h' * 43}',
          state: 's' * 43,
        ),
      );
      await rejects(view(approvalUri: '$link&extra=1', state: 's' * 43));
      await rejects(view(approvalUri: link, state: 'short'));
    });
  });

  group('owner transfer screens', () {
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

    Future<void> openWallet(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('open-wallet-USD')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-wallet-USD')));
      await tester.pumpAndSettle();
    }

    testWidgets('transfer from a wallet through approval to the receipt', (
      tester,
    ) async {
      tall(tester);
      final session = await signedIn();
      final gateway = FakeShopGateway()..profile = fundedProfile();
      final native = _Native();
      final prefs = MerchantPreferences();
      await tester.pumpWidget(
        MerchantApp(
          preferences: prefs,
          session: session,
          shopGateway: gateway,
          transferNative: native,
          alertEffects: _Silent(),
        ),
      );
      await openWallet(tester);
      expect(find.text('Transfer to my wallet'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wallet-transfer')));
      await tester.pumpAndSettle();

      // Validation: the wallet balance is the ceiling, and precision follows the currency.
      await tester.enterText(
        find.byKey(const ValueKey('transfer-amount-field')),
        '50.01',
      );
      await tester.tap(find.byKey(const ValueKey('transfer-create')));
      await tester.pumpAndSettle();
      expect(find.text('More than the wallet balance'), findsOneWidget);
      expect(gateway.transferKeys, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('transfer-amount-field')),
        '12.50',
      );
      await tester.tap(find.byKey(const ValueKey('transfer-create')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        tester.widget<Text>(find.byKey(const ValueKey('transfer-amount'))).data,
        r'$12.50',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('transfer-destination')))
            .data,
        'From your US Dollar business wallet to your wallet •••• 5678',
      );
      expect(find.byKey(const ValueKey('transfer-open')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('transfer-open')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        native.opened.single,
        startsWith('$transferApprovalBase?intentId='),
      );

      final loadsBefore = gateway.loads;
      gateway.resolveTransfer(
        gateway.transfers.keys.single,
        TransferStatus.completed,
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('transfer-completed')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('transfer-reference')))
            .data,
        'TXN-OWNER-0001',
      );
      expect(
        gateway.loads,
        greaterThan(loadsBefore),
        reason: 'balances refresh',
      );

      await tester.tap(find.byKey(const ValueKey('transfer-done')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wallet-detail-card')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      prefs.dispose();
    });

    testWidgets(
      'the action is hidden by an empty wallet or a restricted shop',
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
            transferNative: _Native(),
            alertEffects: _Silent(),
          ),
        );
        await openWallet(tester);
        final button = tester.widget<FilledButton>(
          find.byKey(const ValueKey('wallet-transfer')),
        );
        expect(button.onPressed, isNull, reason: 'zero balance');
        await tester.pumpWidget(const SizedBox.shrink());
        session.dispose();
        prefs.dispose();
      },
    );

    for (final (status, text, key) in [
      (
        TransferStatus.denied,
        'You declined this transfer in Kesor Bank. Nothing was moved.',
        'transfer-denied',
      ),
      (
        TransferStatus.expired,
        'This transfer expired before it was approved. Nothing was moved.',
        'transfer-expired',
      ),
      (
        TransferStatus.cancelled,
        'This transfer was cancelled. Nothing was moved.',
        'transfer-cancelled',
      ),
      (
        TransferStatus.failed,
        'The business wallet balance was not enough when you approved. Nothing was moved.',
        'transfer-failed',
      ),
    ]) {
      testWidgets('${status.name} is explained and moves nothing', (
        tester,
      ) async {
        tall(tester);
        final gateway = FakeShopGateway()..profile = fundedProfile();
        final controller = controllerFor(
          gateway,
          MemoryHandoffStore(),
          _Native(),
        );
        await controller.create(
          sourceAccountNumber: '2234567890',
          amount: '5.00',
        );
        gateway.resolveTransfer(
          controller.transfer!.id,
          status,
          failureCode: status == TransferStatus.failed
              ? 'INSUFFICIENT_FUNDS'
              : null,
        );
        await controller.refresh();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(Brightness.light),
            home: MerchantStrings(
              khmer: false,
              child: OwnerTransferPage(
                controller: controller,
                wallet: usdWallet,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byKey(ValueKey(key)), findsOneWidget);
        expect(find.text(text), findsOneWidget);
        expect(find.byKey(const ValueKey('transfer-completed')), findsNothing);
        expect(find.byKey(const ValueKey('transfer-open')), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      });
    }

    testWidgets('the Khmer waiting screen fits at large text', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final gateway = FakeShopGateway()..profile = fundedProfile();
      final controller = controllerFor(
        gateway,
        MemoryHandoffStore(),
        _Native(),
      );
      await controller.create(
        sourceAccountNumber: '1234567890',
        amount: '25000',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Brightness.light, locale: const Locale('km')),
          home: MerchantStrings(
            khmer: true,
            child: OwnerTransferPage(controller: controller, wallet: khrWallet),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('transfer-amount'))).data,
        '25,000 ៛',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  });
}
