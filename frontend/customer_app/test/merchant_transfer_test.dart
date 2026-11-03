import 'dart:convert';

import 'package:customer_app/app/app_preferences.dart';
import 'package:customer_app/app/banking_app.dart';
import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/features/accounts/account_gateway.dart'
    show RecentPosting;
import 'package:customer_app/features/auth/presentation/app_pin_page.dart';
import 'package:customer_app/features/home/presentation/locked_home_page.dart';
import 'package:customer_app/features/merchant/merchant_approval_screen.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:customer_app/features/merchant/merchant_approval.dart';
import 'package:customer_app/features/merchant/merchant_transfer_approval.dart';
import 'package:customer_app/features/merchant/merchant_transfer_approval_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kesor_auth_handoff/kesor_auth_handoff.dart';

import 'settings_test.dart' show settingsSession, settingsHost;

const intentId = '33333333-3333-4333-8333-333333333333';
final handoff = 'h' * 43, state = 's' * 43;

class TransferNative extends NativeHandoff {
  final transfers = <String>[], signIns = <String>[], opened = <String>[];
  String? error;
  @override
  Future<String?> take() async => signIns.isEmpty ? null : signIns.removeAt(0);
  @override
  Future<String?> takeTransfer() async =>
      transfers.isEmpty ? null : transfers.removeAt(0);
  @override
  Future<void> verify() async {
    if (error != null) throw HandoffFailure(error!);
  }

  @override
  Future<void> open(String uri) async => throw StateError('sign-in open');
  @override
  Future<void> openTransfer(String uri) async {
    await verify();
    opened.add(uri);
  }
}

class TransferRig {
  TransferRig(this.session) {
    api = HandoffApi(
      'http://localhost:8080/api/v1',
      client: MockClient(handle),
    );
    model = build();
  }
  final SessionController session;
  final store = MemoryHandoffStore(), native = TransferNative();
  late HandoffApi api;
  late MerchantTransferApproval model;
  DateTime now = DateTime.utc(2026, 11, 3);
  String status = 'PENDING';
  bool pinInvalid = false, loseApproval = false, insufficient = false;
  bool blockedBySignIn = false;
  String amount = '12.50', currency = 'USD';
  final requests = <http.Request>[];

  MerchantTransferApproval build() => MerchantTransferApproval(
    session,
    api,
    store,
    native: native,
    clock: () => now,
    blocked: () => blockedBySignIn,
  );

  String get link =>
      '$transferApprovalBase?intentId=$intentId&handoffToken=$handoff';
  String get callback =>
      '$transferCallbackBase?intentId=$intentId&state=$state';
  static const _json = {'content-type': 'application/json; charset=utf-8'};
  http.Response ok(dynamic data) => http.Response(
    jsonEncode({'success': true, 'data': data}),
    200,
    headers: _json,
  );
  http.Response fail(String code, int status) =>
      http.Response(jsonEncode({'error': code}), status, headers: _json);

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    expect(request.headers['Authorization'], startsWith('Bearer '));
    if (request.method == 'GET' && path.endsWith(intentId)) {
      expect(request.headers['X-Merchant-Handoff'], handoff);
      if (status == 'COMPLETED') return fail('OWNER_TRANSFER_COMPLETED', 409);
      if (status != 'PENDING') return fail('OWNER_TRANSFER_$status', 409);
      return ok({
        'intentId': intentId,
        'shopName': 'Sokha Coffee',
        'sourceAccount': '•••• 1234',
        'destinationAccount': '•••• 5678',
        'currency': currency,
        'amount': amount,
        'status': 'PENDING',
        'expiresAt': now.add(const Duration(minutes: 5)).toIso8601String(),
        'serverTime': now.toIso8601String(),
        'merchantPackage': merchantPackage,
      });
    }
    if (path.endsWith('/approve')) {
      expect(jsonDecode(request.body), {
        'handoffToken': handoff,
        'pin': '0427',
      });
      expect(request.headers.containsKey('X-Pin-Proof'), false);
      if (pinInvalid) return fail('PIN_INVALID', 403);
      if (insufficient) {
        status = 'FAILED';
        return ok({
          'intentId': intentId,
          'status': 'FAILED',
          'failureCode': 'INSUFFICIENT_FUNDS',
          'callbackUri': '$callback&error=failed',
          'merchantPackage': merchantPackage,
        });
      }
      status = 'COMPLETED';
      if (loseApproval) throw http.ClientException('lost');
      return ok({
        'intentId': intentId,
        'status': 'COMPLETED',
        'callbackUri': callback,
        'merchantPackage': merchantPackage,
      });
    }
    if (path.endsWith('/deny')) {
      expect(jsonDecode(request.body), {'handoffToken': handoff});
      status = 'DENIED';
      return ok({
        'intentId': intentId,
        'status': 'DENIED',
        'callbackUri': '$callback&error=access_denied',
        'merchantPackage': merchantPackage,
      });
    }
    throw StateError('Unexpected route $path');
  }

  Future<void> start() async {
    native.transfers.add(link);
    await model.initialize();
  }

  void dispose() {
    model.dispose();
    session.dispose();
    api.client.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('links cannot be confused', () {
    test('sign-in and transfer links are different exact shapes', () {
      final signIn = '$approvalBase?attemptId=$intentId&handoffToken=$handoff';
      final transfer =
          '$transferApprovalBase?intentId=$intentId&handoffToken=$handoff';
      expect(approvalBase, isNot(transferApprovalBase));
      expect(callbackBase, isNot(transferCallbackBase));
      expect(
        () => exactLink(signIn, transferApprovalBase, {
          'intentId',
          'handoffToken',
        }),
        throwsA(isA<HandoffFailure>()),
      );
      expect(
        () => exactLink(transfer, approvalBase, {'attemptId', 'handoffToken'}),
        throwsA(isA<HandoffFailure>()),
      );
      // The same-named parameters on the wrong path, and extra parameters, are refused.
      expect(
        () => exactLink(
          '$transferApprovalBase?attemptId=$intentId&handoffToken=$handoff',
          transferApprovalBase,
          {'intentId', 'handoffToken'},
        ),
        throwsA(isA<HandoffFailure>()),
      );
      expect(
        () => exactLink('$transfer&extra=1', transferApprovalBase, {
          'intentId',
          'handoffToken',
        }),
        throwsA(isA<HandoffFailure>()),
      );
    });

    test(
      'a sign-in link in the transfer slot, or the reverse, starts nothing',
      () async {
        final r = TransferRig(await settingsSession());
        addTearDown(r.dispose);
        r.native.transfers.add(
          '$approvalBase?attemptId=$intentId&handoffToken=$handoff',
        );
        await r.model.initialize();
        expect(r.model.hasRequest, isFalse);

        // The sign-in coordinator ignores a transfer-shaped link handed to its own channel.
        final signIn = MerchantApproval(
          r.session,
          r.api,
          MemoryHandoffStore(),
          native: r.native,
          clock: () => r.now,
        );
        addTearDown(signIn.dispose);
        r.native.signIns.add(r.link);
        await signIn.initialize();
        expect(signIn.hasRequest, isFalse);
        expect(r.requests, isEmpty);
      },
    );

    test(
      'a transfer link is left untaken while a sign-in request is active',
      () async {
        final r = TransferRig(await settingsSession())..blockedBySignIn = true;
        addTearDown(r.dispose);
        await r.start();
        expect(r.model.hasRequest, isFalse);
        expect(r.native.transfers, [
          r.link,
        ], reason: 'left for later, not dropped');
        r.blockedBySignIn = false;
        await r.model.poll();
        expect(r.model.hasRequest, isTrue);
      },
    );
  });

  group('transfer approval', () {
    test(
      'shows the exact intent, sends fresh PIN only to the server and returns',
      () async {
        final r = TransferRig(await settingsSession(withPin: true));
        addTearDown(r.dispose);
        await r.start();
        expect(r.model.details!['amount'], '12.50');
        expect(r.model.details!['destinationAccount'], '•••• 5678');
        expect(r.model.canDecide, isTrue);
        await r.model.decide(pin: '0427');
        expect(r.native.opened.single, r.callback);
        expect(r.native.opened.single, isNot(contains('0427')));
        expect(r.model.hasRequest, isFalse);
        expect(r.store.values.containsKey('transfer-approval'), isFalse);
        expect(
          r.requests.where((q) => q.url.path.endsWith('/approve')),
          hasLength(1),
        );
      },
    );

    test(
      'declining has no PIN and returns the access_denied callback',
      () async {
        final r = TransferRig(await settingsSession());
        addTearDown(r.dispose);
        await r.start();
        await r.model.decide();
        expect(r.native.opened.single, '${r.callback}&error=access_denied');
        expect(r.model.hasRequest, isFalse);
      },
    );

    test(
      'a wrong PIN keeps the request open and never opens Merchant',
      () async {
        final r = TransferRig(await settingsSession())..pinInvalid = true;
        addTearDown(r.dispose);
        await r.start();
        await r.model.decide(pin: '0427');
        expect(r.model.message, 'PIN_INVALID');
        expect(r.model.canDecide, isTrue);
        expect(r.native.opened, isEmpty);
      },
    );

    test(
      'an unverified Merchant app is refused before anything is approved',
      () async {
        final r = TransferRig(await settingsSession());
        addTearDown(r.dispose);
        await r.start();
        r.native.error = 'HANDOFF_UNAVAILABLE';
        await r.model.decide(pin: '0427');
        expect(
          r.requests.where((q) => q.url.path.endsWith('/approve')),
          isEmpty,
        );
        expect(r.native.opened, isEmpty);
      },
    );

    test(
      'insufficient funds waits for the owner instead of returning silently',
      () async {
        final r = TransferRig(await settingsSession())..insufficient = true;
        addTearDown(r.dispose);
        await r.start();
        await r.model.decide(pin: '0427');
        expect(r.model.outcome, 'FAILED');
        expect(r.native.opened, isEmpty);
        expect(r.model.canReturn, isTrue);
        await r.model.returnToMerchant();
        expect(r.native.opened.single, '${r.callback}&error=failed');
        expect(r.model.hasRequest, isFalse);
      },
    );

    test('a lost approval response is resolved by reloading, never by re-approving', () async {
      final r = TransferRig(await settingsSession())..loseApproval = true;
      addTearDown(r.dispose);
      await r.start();
      await r.model.decide(pin: '0427');
      expect(r.model.message, 'OFFLINE');
      expect(r.model.canDecide, isFalse);
      await r.model.loadDetails();
      expect(r.model.message, 'OWNER_TRANSFER_COMPLETED');
      expect(r.model.details, isNull);
      await r.model.decide(pin: '0427');
      expect(
        r.requests.where((q) => q.url.path.endsWith('/approve')),
        hasLength(1),
      );
    });

    test('a forged or mismatched response is rejected', () async {
      final bad = TransferRig(await settingsSession());
      addTearDown(bad.dispose);
      // A callback for another intent must never be opened.
      bad.api = HandoffApi(
        'http://localhost:8080/api/v1',
        client: MockClient((request) async {
          if (request.method == 'GET') return bad.handle(request);
          return bad.ok({
            'intentId': intentId,
            'status': 'COMPLETED',
            'callbackUri':
                '$transferCallbackBase?intentId=44444444-4444-4444-8444-444444444444&state=$state',
            'merchantPackage': merchantPackage,
          });
        }),
      );
      bad.model.dispose();
      bad.model = bad.build();
      await bad.start();
      await bad.model.decide(pin: '0427');
      expect(bad.native.opened, isEmpty);
      expect(bad.model.message, 'INVALID_RESPONSE');
    });

    test(
      'a request is never replaced, expires locally and survives recreation',
      () async {
        final r = TransferRig(await settingsSession());
        addTearDown(r.dispose);
        await r.start();
        r.native.transfers.add(
          r.link.replaceFirst(intentId, '55555555-5555-4555-8555-555555555555'),
        );
        await r.model.poll();
        expect(r.model.pending!['id'], intentId);

        final raw = r.store.values['transfer-approval']!;
        expect(raw, isNot(contains('0427')));
        expect(raw, isNot(contains('accessToken')));
        r.model.dispose();
        r.model = r.build();
        await r.model.initialize();
        expect(r.model.details!['intentId'], intentId);

        r.now = r.now.add(const Duration(minutes: 6));
        await r.model.poll();
        expect(r.model.hasRequest, isFalse);
      },
    );

    test('a request resumes after the Customer PIN lock', () async {
      final r = TransferRig(await settingsSession(withPin: true));
      addTearDown(r.dispose);
      r.session.lockApp();
      await r.start();
      expect(r.model.hasRequest, isTrue);
      expect(r.model.details, isNull);
      await r.session.submitPin('0427');
      await r.model.poll();
      expect(r.model.details, isNotNull);
    });

    test(
      'a request that is already over is reported without approving',
      () async {
        final r = TransferRig(await settingsSession())..status = 'CANCELLED';
        addTearDown(r.dispose);
        await r.start();
        expect(r.model.message, 'OWNER_TRANSFER_CANCELLED');
        expect(r.model.canDecide, isFalse);
        expect(
          r.requests.where((q) => q.url.path.endsWith('/approve')),
          isEmpty,
        );
      },
    );
  });

  group('transfer screen', () {
    Future<void> show(
      WidgetTester tester,
      TransferRig r,
      AppPreferences prefs, {
      Size size = const Size(320, 1600),
      double scale = 1,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        settingsHost(
          prefs,
          MerchantTransferApprovalScreen(approval: r.model, session: r.session),
        ),
      );
      await tester.pump();
    }

    testWidgets(
      'English: the exact amount is large and both wallets are masked',
      (tester) async {
        final r = TransferRig(await settingsSession(withPin: true));
        addTearDown(r.dispose);
        await r.start();
        final prefs = AppPreferences();
        addTearDown(prefs.dispose);
        await show(tester, r, prefs);
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('transfer-amount')))
              .data,
          r'$12.50',
        );
        expect(find.text('Sokha Coffee'), findsOneWidget);
        expect(find.text('•••• 1234'), findsOneWidget);
        expect(find.text('•••• 5678'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('transfer-countdown')),
          findsOneWidget,
        );
        expect(find.text('Approve with PIN'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        r.model.dispose();
      },
    );

    testWidgets('Khmer at large text fits without overflow', (tester) async {
      final r = TransferRig(await settingsSession(withPin: true))
        ..amount = '25000'
        ..currency = 'KHR';
      addTearDown(r.dispose);
      await r.start();
      final prefs = AppPreferences()..setLanguage(const Locale('km'));
      addTearDown(prefs.dispose);
      await show(tester, r, prefs, size: const Size(320, 3600), scale: 2);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('transfer-amount'))).data,
        '25,000 ៛',
      );
      expect(find.text('អនុម័តដោយ PIN'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      r.model.dispose();
    });

    testWidgets(
      'the PIN clears on privacy cover and the buttons drive the flow',
      (tester) async {
        final r = TransferRig(await settingsSession(withPin: true));
        addTearDown(r.dispose);
        await r.start();
        final prefs = AppPreferences();
        addTearDown(prefs.dispose);
        await show(tester, r, prefs);
        final field = find.byKey(const ValueKey('transfer-pin'));
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('transfer-approve')),
              )
              .onPressed,
          isNull,
        );
        await tester.enterText(field, '0427');
        await tester.pump();
        final controller = tester.widget<TextField>(field).controller!;
        r.session.coverPrivateContent();
        await tester.pump();
        expect(controller.text, isEmpty);

        r.session.uncoverPrivateContent();
        // Covering hides the details; they are fetched again once the app is visible.
        await r.model.loadDetails();
        await tester.pump();
        await tester.enterText(field, '0427');
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey('transfer-approve')),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('transfer-approve')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(r.native.opened.single, r.callback);
        expect(controller.text, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        r.model.dispose();
      },
    );

    testWidgets('declining from the screen sends no PIN', (tester) async {
      final r = TransferRig(await settingsSession(withPin: true));
      addTearDown(r.dispose);
      await r.start();
      final prefs = AppPreferences();
      addTearDown(prefs.dispose);
      await show(tester, r, prefs);
      await tester.ensureVisible(find.byKey(const ValueKey('transfer-deny')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('transfer-deny')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(r.native.opened.single, contains('error=access_denied'));
      await tester.pumpWidget(const SizedBox.shrink());
      r.model.dispose();
    });
  });

  group('app shell', () {
    final config = AppConfig(
      apiBaseUrl: 'http://localhost:8080/api/v1',
      environment: 'dev',
      mode: 'demo',
    );

    void request(TransferRig r) {
      r.model.pending = {
        'id': intentId,
        'handoff': handoff,
        'owner': r.session.identity?.userId,
        'until': r.now.add(const Duration(minutes: 5)).toIso8601String(),
      };
      r.model.details = {
        'intentId': intentId,
        'shopName': 'Sokha Coffee',
        'sourceAccount': '•••• 1234',
        'destinationAccount': '•••• 5678',
        'currency': 'USD',
        'amount': '12.50',
        'status': 'PENDING',
        'expiresAt': r.now.add(const Duration(minutes: 5)).toIso8601String(),
        'serverTime': r.now.toIso8601String(),
      };
    }

    Future<void> pump(
      WidgetTester tester,
      TransferRig r, {
      MerchantApproval? signIn,
    }) async {
      tester.view.physicalSize = const Size(440, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        BankingApp(
          session: r.session,
          config: config,
          merchantApproval: signIn,
          merchantTransfer: r.model,
        ),
      );
      await tester.pump();
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
    }

    testWidgets(
      'a signed-in owner with a pending transfer sees its approval screen',
      (tester) async {
        final r = TransferRig(await settingsSession(withPin: true));
        addTearDown(r.dispose);
        request(r);
        await pump(tester, r);
        expect(find.byType(MerchantTransferApprovalScreen), findsOneWidget);
        expect(find.text(r'$12.50'), findsOneWidget);
        await close(tester);
      },
    );

    testWidgets('a pending sign-in request wins over a transfer', (
      tester,
    ) async {
      final r = TransferRig(await settingsSession(withPin: true));
      addTearDown(r.dispose);
      request(r);
      final signIn = MerchantApproval(
        r.session,
        r.api,
        MemoryHandoffStore(),
        native: r.native,
      );
      addTearDown(signIn.dispose);
      signIn.pending = {
        'id': intentId,
        'handoff': handoff,
        'until': r.now.add(const Duration(minutes: 2)).toIso8601String(),
      };
      await pump(tester, r, signIn: signIn);
      expect(find.byType(MerchantApprovalScreen), findsOneWidget);
      expect(find.byType(MerchantTransferApprovalScreen), findsNothing);
      await close(tester);
    });

    testWidgets(
      'a PIN-locked app goes straight to the PIN pad for a pending transfer',
      (tester) async {
        final r = TransferRig(await settingsSession(withPin: true));
        addTearDown(r.dispose);
        r.session.lockApp();
        r.model.pending = {
          'id': intentId,
          'handoff': handoff,
          'until': r.now.add(const Duration(minutes: 5)).toIso8601String(),
        };
        await pump(tester, r);
        expect(find.byType(AppPinPage), findsOneWidget);
        expect(find.byType(LockedHomePage), findsNothing);
        expect(find.byType(MerchantTransferApprovalScreen), findsNothing);
        await close(tester);
      },
    );

    testWidgets('a signed-out app says a transfer is waiting', (tester) async {
      final r = TransferRig(await settingsSession(withPin: true));
      addTearDown(r.dispose);
      await r.session.signOut();
      r.model.pending = {
        'id': intentId,
        'handoff': handoff,
        'until': r.now.add(const Duration(minutes: 5)).toIso8601String(),
      };
      await pump(tester, r);
      expect(
        find.text(
          'A Merchant transfer is waiting. Sign in to Kesor Bank to review it.',
        ),
        findsOneWidget,
      );
      expect(find.byType(MerchantTransferApprovalScreen), findsNothing);
      await close(tester);
    });
  });

  group('history', () {
    test('an owner transfer named after the shop parses like any transfer', () {
      final posting = RecentPosting.fromJson({
        'referenceNumber': 'TXN-OWNER-0001',
        'sourceAccountNumber': '2234567890',
        'destinationAccountNumber': '3334567890',
        'transactionType': 'TRANSFER',
        'status': 'SUCCESS',
        'currency': 'USD',
        'amount': '12.50',
        'fee': '0.00',
        'createdAt': '2026-11-03T10:00:00+07:00',
        'remark': 'Transfer to owner wallet',
        'sourceName': 'Sokha Coffee',
        'destinationName': 'Seng Sovanreach',
        'operation': 'OWNER_TRANSFER',
      }, '3334567890');
      expect(posting.operation, 'OWNER_TRANSFER');
      expect(posting.sourceName, 'Sokha Coffee');
      expect(posting.type, 'TRANSFER');
    });
  });
}
