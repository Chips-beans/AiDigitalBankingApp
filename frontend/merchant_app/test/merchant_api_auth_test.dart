import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kesor_auth_handoff/kesor_auth_handoff.dart';
import 'package:merchant_app/core/merchant_config.dart';
import 'package:merchant_app/features/auth/merchant_api_auth.dart';
import 'package:merchant_app/features/auth/merchant_session.dart';

const id = '11111111-1111-4111-8111-111111111111';
final code = 'c' * 43, handoff = 'h' * 43;

class FakeNative extends NativeHandoff {
  final incoming = <String>[];
  final opened = <String>[];
  String? issue;
  void Function(String)? onOpen;
  @override
  Future<String?> take() async =>
      incoming.isEmpty ? null : incoming.removeAt(0);
  @override
  Future<void> verify() async {
    if (issue != null) throw HandoffFailure(issue!);
  }

  @override
  Future<void> open(String uri) async {
    await verify();
    opened.add(uri);
    onOpen?.call(uri);
  }
}

class Rig {
  Rig() {
    api = HandoffApi(config.apiBaseUrl, client: MockClient(handle));
    gateway = MerchantApiAuth(
      config,
      api: api,
      store: store,
      native: native,
      clock: () => now,
    );
    native.onOpen = (_) {
      if (sendCallback) {
        native.incoming.add(
          '$callbackBase?code=$code&state=${start!['state']}',
        );
      }
    };
  }
  final config = MerchantConfig(
    apiBaseUrl: 'http://localhost:8080/api/v1',
    environment: 'dev',
  );
  final store = MemoryHandoffStore(), native = FakeNative();
  late HandoffApi api;
  late MerchantApiAuth gateway;
  DateTime now = DateTime.utc(2026, 10, 31);
  Map<String, dynamic>? start;
  final requests = <http.Request>[], exchanges = <Map<String, dynamic>>[];
  bool sendCallback = true,
      loseExchange = false,
      offlineCancel = false,
      revoked = false;
  String onboarding = 'SHOP_REQUIRED';
  Completer<void>? exchangeGate, startGate, identityGate;
  http.Response ok(dynamic data) =>
      http.Response(jsonEncode({'success': true, 'data': data}), 200);
  Future<http.Response> handle(http.Request req) async {
    requests.add(req);
    final path = req.url.path.replaceFirst('/api/v1', '');
    if (path == '/merchant-auth/attempts') {
      start = jsonDecode(req.body);
      expect(req.headers.containsKey('Authorization'), false);
      expect(start!['codeChallengeMethod'], 'S256');
      expect(start!['attemptSecretHash'], matches(r'^[0-9a-f]{64}$'));
      final persisted = jsonDecode(store.values['auth']!)['pending'];
      expect(challenge(persisted['verifier']), start!['codeChallenge']);
      expect(secretHash(persisted['secret']), start!['attemptSecretHash']);
      await startGate?.future;
      return ok({
        'attemptId': id,
        'expiresAt': now.add(const Duration(seconds: 120)).toIso8601String(),
        'approvalUri': '$approvalBase?attemptId=$id&handoffToken=$handoff',
        'customerPackage': customerPackage,
      });
    }
    if (path.endsWith('/status')) {
      return ok({'attemptId': id, 'status': 'PENDING'});
    }
    if (path.endsWith('/cancel')) {
      if (offlineCancel) throw http.ClientException('offline');
      return ok({'status': 'CANCELLED'});
    }
    if (path == '/merchant-auth/exchange') {
      expect(req.headers.containsKey('Authorization'), false);
      exchanges.add(jsonDecode(req.body));
      await exchangeGate?.future;
      if (loseExchange) {
        loseExchange = false;
        throw http.ClientException('response lost');
      }
      return ok({
        'accessToken': 'synthetic-access',
        'refreshToken': 'synthetic-refresh',
        'expiresInMs': 300000,
      });
    }
    if (path == '/merchant-auth/refresh') {
      return ok({
        'accessToken': 'rotated-access',
        'refreshToken': 'rotated-refresh',
        'expiresInMs': 300000,
      });
    }
    if (path == '/merchant-auth/logout') return ok(null);
    if (path == '/merchant-auth/session') {
      await identityGate?.future;
      if (revoked) {
        return http.Response(jsonEncode({'error': 'SESSION_INVALID'}), 401);
      }
      return ok({
        'sessionId': id,
        'ownerId': 42,
        'clientId': merchantClient,
        'onboardingState': onboarding,
        if (onboarding == 'READY' || onboarding == 'RESTRICTED')
          'shop': {
            'merchantId': 'shop-1',
            'storeName': 'Kesor shop',
            'status': onboarding == 'READY' ? 'ACTIVE' : 'SUSPENDED',
          },
      });
    }
    throw StateError('Unexpected test route $path');
  }

  Future<void> until(bool Function() ready) async {
    for (var i = 0; i < 100 && !ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(ready(), true);
  }
}

Matcher issue(MerchantAuthIssue value) =>
    isA<MerchantAuthFailure>().having((e) => e.issue, 'issue', value);

class SwitchableStore implements HandoffStore {
  SwitchableStore(this.delegate);
  final HandoffStore delegate;
  bool failWrites = false;
  @override
  Future<String?> read(String key) => delegate.read(key);
  @override
  Future<void> write(String key, String? value) async {
    if (failWrites) {
      throw StateError('Synthetic storage failure');
    }
    await delegate.write(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'storage failure still sends cancellation and logout to the server',
    () async {
      final r = Rig()..loseExchange = true;
      final store = SwitchableStore(r.store);
      final gateway = MerchantApiAuth(
        r.config,
        api: r.api,
        store: store,
        native: r.native,
        clock: () => r.now,
      );
      await expectLater(
        gateway.authorize(),
        throwsA(issue(MerchantAuthIssue.uncertain)),
      );
      store.failWrites = true;
      await expectLater(
        gateway.cancel(),
        throwsA(
          isA<MerchantAuthFailure>()
              .having(
                (e) => e.issue,
                'issue',
                MerchantAuthIssue.storageUnavailable,
              )
              .having(
                (e) => e.diagnostic?.stage,
                'stage',
                MerchantAuthStage.storageWrite,
              ),
        ),
      );
      expect(r.requests.last.url.path, endsWith('/cancel'));
      store.failWrites = false;
      await gateway.authorize();
      store.failWrites = true;
      await expectLater(
        gateway.signOut(),
        throwsA(
          isA<MerchantAuthFailure>()
              .having(
                (e) => e.issue,
                'issue',
                MerchantAuthIssue.storageUnavailable,
              )
              .having(
                (e) => e.diagnostic?.stage,
                'stage',
                MerchantAuthStage.storageWrite,
              ),
        ),
      );
      expect(r.requests.last.url.path, '/api/v1/merchant-auth/logout');
    },
  );
  test(
    'exact links reject forgery, duplicate parameters and alternate paths',
    () {
      for (final link in [
        '$callbackBase?code=$code&state=${'s' * 43}&state=${'s' * 43}',
        '$callbackBase?code=$code&state=${'s' * 43}&extra=x',
        '$callbackBase?code=$code&state=${'s' * 43}#fragment',
        'kesormerchant://auth:80/callback?code=$code&state=${'s' * 43}',
        'kesormerchant://auth/%63allback?code=$code&state=${'s' * 43}',
        'kesormerchant://attacker/callback?code=$code&state=${'s' * 43}',
      ]) {
        expect(
          () => exactLink(link, callbackBase, {'code', 'state'}),
          throwsA(isA<HandoffFailure>()),
        );
      }
      expect(secureEquals('abc', 'abc'), true);
      expect(secureEquals('abc', 'abd'), false);
    },
  );
  test(
    'normal sign-in uses immutable PKCE credentials and erases pending secrets',
    () async {
      final r = Rig();
      final identity = await r.gateway.authorize();
      expect(identity.ownerId, 42);
      expect(identity.shop, isNull);
      expect(r.native.opened.single, startsWith(approvalBase));
      expect(jsonDecode(r.store.values['auth']!)['pending'], isNull);
      expect(r.exchanges.single['state'], r.start!['state']);
      expect(r.requests.any((q) => q.url.path.contains('/auth/me')), false);
    },
  );
  test(
    'missing Customer app starts no attempt or alternate identity',
    () async {
      final r = Rig()..native.issue = 'PEER_MISSING';
      await expectLater(
        r.gateway.authorize(),
        throwsA(issue(MerchantAuthIssue.customerMissing)),
      );
      expect(r.requests, isEmpty);
    },
  );
  test(
    'unsolicited wrong-state callback is ignored before valid callback',
    () async {
      final r = Rig();
      r.native.incoming.add('$callbackBase?code=$code&state=${'x' * 43}');
      await r.gateway.authorize();
      expect(r.exchanges.length, 1);
    },
  );
  test('response loss never auto replays; process restore requires explicit same-body recovery', () async {
    final r = Rig()..loseExchange = true;
    await expectLater(
      r.gateway.authorize(),
      throwsA(issue(MerchantAuthIssue.uncertain)),
    );
    expect(r.exchanges.length, 1);
    final restored = MerchantApiAuth(
      r.config,
      api: r.api,
      store: r.store,
      native: r.native,
      clock: () => r.now,
    );
    await expectLater(
      restored.restore(),
      throwsA(issue(MerchantAuthIssue.uncertain)),
    );
    expect(r.exchanges.length, 1);
    expect((await restored.recover()).ownerId, 42);
    expect(r.exchanges.length, 2);
    expect(r.exchanges[0], r.exchanges[1]);
  });
  test('recovery after sixty seconds cancels instead of exchanging', () async {
    final r = Rig()..loseExchange = true;
    await expectLater(
      r.gateway.authorize(),
      throwsA(issue(MerchantAuthIssue.uncertain)),
    );
    r.now = r.now.add(const Duration(seconds: 61));
    await expectLater(
      r.gateway.recover(),
      throwsA(issue(MerchantAuthIssue.expired)),
    );
    expect(r.exchanges.length, 1);
    expect(r.requests.last.url.path, endsWith('/cancel'));
  });
  test(
    'cancel racing exchange rejects late pair and calls server cancellation',
    () async {
      final r = Rig()..exchangeGate = Completer<void>();
      final result = expectLater(
        r.gateway.authorize(),
        throwsA(isA<MerchantAuthFailure>()),
      );
      await r.until(() => r.exchanges.isNotEmpty);
      await r.gateway.cancel();
      r.exchangeGate!.complete();
      await result;
      expect(r.requests.any((q) => q.url.path.endsWith('/cancel')), true);
      expect(jsonDecode(r.store.values['auth']!)['tokens'], isNull);
    },
  );
  test(
    'cancel racing start waits for late attempt ID before opening Customer',
    () async {
      final r = Rig()..startGate = Completer<void>();
      final result = expectLater(
        r.gateway.authorize(),
        throwsA(isA<MerchantAuthFailure>()),
      );
      await r.until(() => r.start != null);
      await r.gateway.cancel();
      r.startGate!.complete();
      await result;
      expect(r.native.opened, isEmpty);
      expect(r.requests.last.url.path, endsWith('/cancel'));
    },
  );
  test('offline cancellation persists a tombstone and blocks recovery across app death', () async {
    final r = Rig()..loseExchange = true;
    await expectLater(
      r.gateway.authorize(),
      throwsA(issue(MerchantAuthIssue.uncertain)),
    );
    r.offlineCancel = true;
    await expectLater(
      r.gateway.cancel(),
      throwsA(
        isA<MerchantAuthFailure>()
            .having((e) => e.issue, 'issue', MerchantAuthIssue.offline)
            .having(
              (e) => e.diagnostic?.stage,
              'stage',
              MerchantAuthStage.cancel,
            ),
      ),
    );
    final restored = MerchantApiAuth(
      r.config,
      api: r.api,
      store: r.store,
      native: r.native,
      clock: () => r.now,
    );
    await expectLater(
      restored.restore(),
      throwsA(issue(MerchantAuthIssue.offline)),
    );
    expect(r.exchanges.length, 1);
    r.offlineCancel = false;
    expect(await restored.restore(), isNull);
  });
  test('cancel during identity read revokes already-saved session', () async {
    final r = Rig()..identityGate = Completer<void>();
    final result = expectLater(
      r.gateway.authorize(),
      throwsA(isA<MerchantAuthFailure>()),
    );
    await r.until(() => r.requests.any((q) => q.url.path.endsWith('/session')));
    await r.gateway.cancel();
    r.identityGate!.complete();
    await result;
    expect(r.requests.any((q) => q.url.path.endsWith('/logout')), true);
    expect(jsonDecode(r.store.values['auth']!)['tokens'], isNull);
  });
  test(
    'restore uses Merchant identity, rotates refresh and observes revocation',
    () async {
      final r = Rig();
      await r.gateway.authorize();
      r.now = r.now.add(const Duration(minutes: 6));
      final restored = MerchantApiAuth(
        r.config,
        api: r.api,
        store: r.store,
        native: r.native,
        clock: () => r.now,
      );
      expect((await restored.restore())!.ownerId, 42);
      expect(
        r.requests
            .where((q) => q.url.path.endsWith('/refresh'))
            .single
            .url
            .path,
        '/api/v1/merchant-auth/refresh',
      );
      expect(r.native.opened.length, 1);
      r.revoked = true;
      await expectLater(
        restored.validate(),
        throwsA(issue(MerchantAuthIssue.expired)),
      );
      expect(jsonDecode(r.store.values['auth']!)['tokens'], isNull);
    },
  );
  test('server onboarding states route without inventing wallets', () async {
    for (final state in ['READY', 'RESTRICTED', 'RECOVERY_REQUIRED']) {
      final r = Rig()..onboarding = state;
      final session = MerchantSession(r.gateway);
      await session.signIn();
      expect(session.phase, switch (state) {
        'READY' => MerchantPhase.ready,
        'RESTRICTED' => MerchantPhase.restricted,
        _ => MerchantPhase.recoveryRequired,
      });
      session.dispose();
    }
  });
  test('logout uses Merchant route and retains installation ID', () async {
    final r = Rig();
    await r.gateway.authorize();
    final installation = r.store.values['installation'];
    await r.gateway.signOut();
    expect(r.requests.last.url.path, '/api/v1/merchant-auth/logout');
    expect(r.store.values['installation'], installation);
    expect(jsonDecode(r.store.values['auth']!), isEmpty);
  });
}
