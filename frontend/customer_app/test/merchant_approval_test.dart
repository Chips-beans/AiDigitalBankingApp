import 'dart:async';
import 'dart:convert';

import 'package:customer_app/features/merchant/merchant_approval.dart';
import 'package:customer_app/features/merchant/merchant_approval_screen.dart';
import 'package:customer_app/features/merchant/merchant_sessions_screen.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:customer_app/app/app_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kesor_auth_handoff/kesor_auth_handoff.dart';

import 'settings_test.dart' show settingsSession, settingsHost;

const requestId = '11111111-1111-4111-8111-111111111111';
final handoffToken = 'h' * 43, state = 's' * 43, code = 'c' * 43;

class ApprovalNative extends NativeHandoff {
  final queue = <String>[], opened = <String>[];
  String? error;
  @override
  Future<String?> take() async => queue.isEmpty ? null : queue.removeAt(0);
  @override
  Future<void> verify() async {
    if (error != null) throw HandoffFailure(error!);
  }

  @override
  Future<void> open(String uri) async {
    await verify();
    opened.add(uri);
  }
}

class ApprovalRig {
  ApprovalRig(this.session) {
    api = HandoffApi(
      'http://localhost:8080/api/v1',
      client: MockClient(handle),
    );
    model = MerchantApproval(
      session,
      api,
      store,
      native: native,
      clock: () => now,
    );
  }
  final SessionController session;
  final store = MemoryHandoffStore(), native = ApprovalNative();
  late HandoffApi api;
  late MerchantApproval model;
  DateTime now = DateTime.utc(2026, 10, 31);
  String status = 'PENDING';
  bool pinInvalid = false, loseApproval = false;
  Completer<void>? approvalGate;
  final requests = <http.Request>[];
  String get link =>
      '$approvalBase?attemptId=$requestId&handoffToken=$handoffToken';
  http.Response ok(dynamic data) =>
      http.Response(jsonEncode({'success': true, 'data': data}), 200);
  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    expect(request.headers['Authorization'], startsWith('Bearer '));
    if (request.method == 'GET' && path.endsWith(requestId)) {
      expect(request.headers['X-Merchant-Handoff'], handoffToken);
      if (status != 'PENDING') {
        return http.Response(jsonEncode({'error': 'MERCHANT_AUTH_USED'}), 409);
      }
      return ok({
        'attemptId': requestId,
        'clientName': 'Kesor Merchant',
        'deviceName': 'Android phone',
        'merchantPackage': merchantPackage,
        'status': status,
        'expiresAt': now.add(const Duration(seconds: 120)).toIso8601String(),
      });
    }
    if (path.endsWith('/approve')) {
      final body = jsonDecode(request.body);
      expect(body, {'handoffToken': handoffToken, 'pin': '0427'});
      expect(request.headers.containsKey('X-Pin-Proof'), false);
      await approvalGate?.future;
      if (pinInvalid) {
        return http.Response(jsonEncode({'error': 'PIN_INVALID'}), 403);
      }
      status = 'APPROVED';
      if (loseApproval) throw http.ClientException('lost');
      return ok({
        'callbackUri': '$callbackBase?code=$code&state=$state',
        'merchantPackage': merchantPackage,
      });
    }
    if (path.endsWith('/deny')) {
      expect(jsonDecode(request.body), {'handoffToken': handoffToken});
      status = 'DENIED';
      return ok({
        'callbackUri': '$callbackBase?error=access_denied&state=$state',
        'merchantPackage': merchantPackage,
      });
    }
    if (path.endsWith('/merchant-sessions')) {
      return ok([
        {
          'sessionId': requestId,
          'clientName': 'Kesor Merchant',
          'deviceName': 'Android phone',
          'createdAt': now.toIso8601String(),
          'expiresAt': now.add(const Duration(days: 1)).toIso8601String(),
        },
      ]);
    }
    if (path.endsWith('/revoke')) return ok(null);
    throw StateError('Unexpected route');
  }

  Future<void> start() async {
    native.queue.add(link);
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
  test(
    'Customer views server-owned request then sends fresh PIN only to server',
    () async {
      final r = ApprovalRig(await settingsSession(withPin: true));
      addTearDown(r.dispose);
      await r.start();
      expect(r.model.details!['clientName'], 'Kesor Merchant');
      expect(r.model.canDecide, true);
      await r.model.decide(pin: '0427');
      expect(r.native.opened.single, '$callbackBase?code=$code&state=$state');
      expect(r.native.opened.single, isNot(contains('0427')));
      expect(r.model.hasRequest, false);
      expect(r.store.values.containsKey('approval'), false);
    },
  );
  test(
    'denial has no PIN/code and returns registered error callback',
    () async {
      final r = ApprovalRig(await settingsSession());
      addTearDown(r.dispose);
      await r.start();
      await r.model.decide();
      expect(r.native.opened.single, contains('error=access_denied'));
      expect(r.native.opened.single, isNot(contains('code=')));
    },
  );
  test(
    'untrusted links fail and a second request cannot silently replace one',
    () async {
      final r = ApprovalRig(await settingsSession());
      addTearDown(r.dispose);
      r.native.queue.add('${r.link}&handoffToken=$handoffToken');
      await r.model.initialize();
      expect(r.model.hasRequest, false);
      r.native.queue.add(r.link);
      await r.model.poll();
      r.native.queue.add(
        r.link.replaceFirst(requestId, '22222222-2222-4222-8222-222222222222'),
      );
      await r.model.poll();
      expect(r.model.pending!['id'], requestId);
    },
  );
  test(
    'PIN mismatch remains a pending request and never opens Merchant',
    () async {
      final r = ApprovalRig(await settingsSession())..pinInvalid = true;
      addTearDown(r.dispose);
      await r.start();
      await r.model.decide(pin: '0427');
      expect(r.model.message, 'PIN_INVALID');
      expect(r.model.canDecide, true);
      expect(r.native.opened, isEmpty);
    },
  );
  test('missing or untrusted Merchant is checked before approving', () async {
    final r = ApprovalRig(await settingsSession());
    addTearDown(r.dispose);
    await r.start();
    r.native.error = 'HANDOFF_UNAVAILABLE';
    await r.model.decide(pin: '0427');
    expect(r.requests.where((q) => q.url.path.endsWith('/approve')), isEmpty);
    expect(r.native.opened, isEmpty);
  });
  test(
    'uncertain approval reloads server state and cannot automatically resend',
    () async {
      final r = ApprovalRig(await settingsSession())..loseApproval = true;
      addTearDown(r.dispose);
      await r.start();
      await r.model.decide(pin: '0427');
      expect(r.model.canDecide, false);
      await r.model.loadDetails();
      expect(r.model.details, isNull);
      expect(r.model.message, 'MERCHANT_AUTH_USED');
      await r.model.decide(pin: '0427');
      expect(
        r.requests.where((q) => q.url.path.endsWith('/approve')).length,
        1,
      );
    },
  );
  test(
    'request resumes after existing Customer PIN lock and expires locally',
    () async {
      final r = ApprovalRig(await settingsSession(withPin: true));
      addTearDown(r.dispose);
      r.session.lockApp();
      await r.start();
      expect(r.model.details, isNull);
      expect(r.model.hasRequest, true);
      await r.session.submitPin('0427');
      await r.model.poll();
      expect(r.model.details, isNotNull);
      r.now = r.now.add(const Duration(seconds: 121));
      await r.model.poll();
      expect(r.model.hasRequest, false);
    },
  );
  test('request survives process recreation without persisting PIN or Customer token', () async {
    final r = ApprovalRig(await settingsSession());
    addTearDown(r.dispose);
    await r.start();
    final raw = r.store.values['approval']!;
    expect(raw, isNot(contains('0427')));
    expect(raw, isNot(contains('accessToken')));
    r.model.dispose();
    r.model = MerchantApproval(
      r.session,
      r.api,
      r.store,
      native: r.native,
      clock: () => r.now,
    );
    await r.model.initialize();
    expect(r.model.details!['attemptId'], requestId);
  });
  testWidgets(
    'approval PIN clears on privacy cover and accessible narrow layout fits',
    (tester) async {
      final r = ApprovalRig(await settingsSession(withPin: true));
      addTearDown(r.dispose);
      await r.start();
      final prefs = AppPreferences();
      addTearDown(prefs.dispose);
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        settingsHost(
          prefs,
          MerchantApprovalScreen(approval: r.model, session: r.session),
        ),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('merchant-approval-pin')),
        '0427',
      );
      final controller = tester
          .widget<TextField>(
            find.byKey(const ValueKey('merchant-approval-pin')),
          )
          .controller!;
      r.session.coverPrivateContent();
      await tester.pump();
      expect(controller.text, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      r.model.dispose();
    },
  );
  testWidgets(
    'Customer can inspect and explicitly revoke owned Merchant session',
    (tester) async {
      final r = ApprovalRig(await settingsSession());
      addTearDown(r.dispose);
      final prefs = AppPreferences();
      addTearDown(prefs.dispose);
      await tester.pumpWidget(
        settingsHost(
          prefs,
          MerchantSessionsScreen(session: r.session, api: r.api, onBack: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Android phone'), findsOneWidget);
      await tester.tap(find.text('Sign out Merchant'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('No active Merchant sessions.'), findsOneWidget);
      expect(r.session.phase, SessionPhase.signedIn);
      expect(r.requests.last.url.path, endsWith('/revoke'));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
