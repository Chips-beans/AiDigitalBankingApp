import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kesor_auth_handoff/kesor_auth_handoff.dart';
import 'package:merchant_app/app/merchant_app.dart';
import 'package:merchant_app/core/merchant_preferences.dart';
import 'package:merchant_app/features/auth/merchant_api_auth.dart';
import 'package:merchant_app/features/auth/merchant_session.dart';

import 'merchant_api_auth_test.dart' show Rig, FakeNative, SwitchableStore;

Matcher failureAt(
  MerchantAuthIssue issue,
  MerchantAuthStage stage,
  String code, {
  int? status,
}) => isA<MerchantAuthFailure>()
    .having((e) => e.issue, 'issue', issue)
    .having((e) => e.diagnostic?.stage, 'stage', stage)
    .having((e) => e.diagnostic?.safeCode, 'code', code)
    .having((e) => e.diagnostic?.httpStatus, 'HTTP status', status);

void intercept(
  Rig rig,
  Future<http.Response?> Function(http.Request) response,
) {
  rig.api = HandoffApi(
    rig.config.apiBaseUrl,
    client: MockClient(
      (req) async => await response(req) ?? await rig.handle(req),
    ),
  );
  rig.gateway = MerchantApiAuth(
    rig.config,
    api: rig.api,
    store: rig.store,
    native: rig.native,
    clock: () => rig.now,
  );
}

class OpenFailureNative extends FakeNative {
  @override
  Future<void> open(String uri) async =>
      throw const HandoffFailure('PEER_OPEN_FAILED');
}

class ReadFailureStore extends MemoryHandoffStore {
  @override
  Future<String?> read(String key) async =>
      throw StateError('private platform error');
}

class DelayedOpenNative extends FakeNative {
  int opens = 0;
  final later = Completer<void>();
  @override
  Future<void> open(String uri) async {
    if (++opens == 2) await later.future;
  }
}

class DiagnosticAuth implements MerchantAuthGateway {
  DiagnosticAuth(this.problem);
  final MerchantAuthFailure problem;
  int starts = 0;
  @override
  Future<MerchantIdentity> authorize() async {
    starts++;
    throw problem;
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<void> signOut() async {}
}

Widget diagnosticApp(MerchantSession session, MerchantPreferences prefs) =>
    MerchantApp(session: session, preferences: prefs);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final status in [200, 401, 403, 429, 503]) {
    test(
      'non-JSON HTTP $status retains status without exposing body',
      () async {
        final api = HandoffApi(
          'http://localhost:8080/api/v1',
          client: MockClient(
            (_) async =>
                http.Response('<html>private response body</html>', status),
          ),
        );
        await expectLater(
          api.request('GET', '/merchant-auth/session'),
          throwsA(
            isA<HandoffFailure>()
                .having((e) => e.code, 'code', 'INVALID_RESPONSE')
                .having((e) => e.status, 'status', status),
          ),
        );
      },
    );
  }

  for (final entry in [
    ('PEER_MISSING', MerchantAuthIssue.customerMissing),
    ('PEER_SIGNATURE_MISMATCH', MerchantAuthIssue.appMismatch),
    ('HANDOFF_UNSUPPORTED_BUILD', MerchantAuthIssue.unsupportedBuild),
  ]) {
    test('${entry.$1} preserves native stage and creates no attempt', () async {
      final r = Rig()..native.issue = entry.$1;
      await expectLater(
        r.gateway.authorize(),
        throwsA(
          failureAt(entry.$2, MerchantAuthStage.verifyCustomer, entry.$1),
        ),
      );
      expect(r.requests, isEmpty);
    });
  }

  test('opening failure is identified and cancels the known attempt', () async {
    final r = Rig();
    final gateway = MerchantApiAuth(
      r.config,
      api: r.api,
      store: r.store,
      native: OpenFailureNative(),
      clock: () => r.now,
    );
    await expectLater(
      gateway.authorize(),
      throwsA(
        failureAt(
          MerchantAuthIssue.openFailed,
          MerchantAuthStage.openCustomer,
          'PEER_OPEN_FAILED',
        ),
      ),
    );
    expect(r.requests.last.url.path, endsWith('/cancel'));
    expect(jsonDecode(r.store.values['auth']!)['pending'], null);
    expect(r.exchanges, isEmpty);
  });

  test(
    'failed start clears only its draft and explicit retry starts fresh',
    () async {
      final r = Rig();
      final starts = <Map<String, dynamic>>[];
      intercept(r, (req) async {
        if (req.url.path.endsWith('/attempts')) {
          starts.add(jsonDecode(req.body) as Map<String, dynamic>);
          if (starts.length == 1) {
            throw http.ClientException('network detail must never reach UI');
          }
        }
        return null;
      });
      await expectLater(
        r.gateway.authorize(),
        throwsA(
          failureAt(
            MerchantAuthIssue.offline,
            MerchantAuthStage.createAttempt,
            'OFFLINE',
          ),
        ),
      );
      expect(jsonDecode(r.store.values['auth']!)['pending'], null);
      expect(r.exchanges, isEmpty);
      expect((await r.gateway.authorize()).ownerId, 42);
      expect(starts.length, 2);
      expect(starts.first['state'], isNot(starts.last['state']));
      expect(
        starts.first['codeChallenge'],
        isNot(starts.last['codeChallenge']),
      );
      expect(r.native.opened.length, 1);
    },
  );

  test(
    'failed start racing cancellation cannot publish a new session',
    () async {
      final r = Rig();
      final gate = Completer<void>();
      var started = false;
      intercept(r, (req) async {
        if (req.url.path.endsWith('/attempts')) {
          started = true;
          await gate.future;
          throw http.ClientException('offline');
        }
        return null;
      });
      final result = expectLater(
        r.gateway.authorize(),
        throwsA(isA<MerchantAuthFailure>()),
      );
      await r.until(() => started);
      await r.gateway.cancel();
      gate.complete();
      await result;
      expect(r.exchanges, isEmpty);
      expect(r.native.opened, isEmpty);
      expect(jsonDecode(r.store.values['auth']!)['pending'], null);
    },
  );

  for (final malformed in [true, false]) {
    test(
      '${malformed ? 'malformed tokens' : 'non-JSON 503'} requires identical exchange recovery',
      () async {
        final r = Rig();
        final bodies = <String>[];
        intercept(r, (req) async {
          if (req.url.path.endsWith('/exchange')) {
            bodies.add(req.body);
            if (bodies.length == 1) {
              return malformed
                  ? r.ok({
                      'accessToken': '',
                      'refreshToken': 'fixture-refresh',
                      'expiresInMs': 300000,
                    })
                  : http.Response('<html>upstream error</html>', 503);
            }
          }
          return null;
        });
        await expectLater(
          r.gateway.authorize(),
          throwsA(
            failureAt(
              MerchantAuthIssue.uncertain,
              MerchantAuthStage.exchange,
              'INVALID_RESPONSE',
              status: malformed ? null : 503,
            ),
          ),
        );
        final saved = jsonDecode(r.store.values['auth']!);
        expect(saved['tokens'], null);
        expect(saved['pending']['code'], isNotNull);
        expect(bodies.length, 1);
        expect((await r.gateway.recover()).ownerId, 42);
        expect(bodies.length, 2);
        expect(bodies.first, bodies.last);
        expect(r.native.opened.length, 1);
      },
    );
  }

  test('saved tokens survive failed identity read and retry does not exchange again', () async {
    final r = Rig();
    var identities = 0;
    intercept(r, (req) async {
      if (req.url.path.endsWith('/session') && identities++ == 0) {
        return http.Response('<html>unavailable</html>', 502);
      }
      return null;
    });
    await expectLater(
      r.gateway.authorize(),
      throwsA(
        failureAt(
          MerchantAuthIssue.serverUnavailable,
          MerchantAuthStage.identity,
          'INVALID_RESPONSE',
          status: 502,
        ),
      ),
    );
    expect(jsonDecode(r.store.values['auth']!)['tokens'], isNotNull);
    expect(jsonDecode(r.store.values['auth']!)['pending'], null);
    expect((await r.gateway.authorize()).ownerId, 42);
    expect(r.exchanges.length, 1);
    expect(r.native.opened.length, 1);
  });

  test(
    'known waiting attempt resumes and can reopen without creating another',
    () async {
      final r = Rig()..sendCallback = false;
      var statuses = 0;
      intercept(r, (req) async {
        if (req.url.path.endsWith('/status') && statuses++ == 0) {
          return http.Response(jsonEncode({'error': 'INTERNAL_ERROR'}), 500);
        }
        return null;
      });
      await expectLater(
        r.gateway.authorize(),
        throwsA(
          failureAt(
            MerchantAuthIssue.serverUnavailable,
            MerchantAuthStage.awaitApproval,
            'INTERNAL_ERROR',
            status: 500,
          ),
        ),
      );
      final saved = r.store.values['auth'];
      final session = MerchantSession(r.gateway);
      addTearDown(session.dispose);
      final next = session.signIn();
      await r.until(() => statuses == 2);
      r.sendCallback = true;
      await session.reopen();
      await next;
      expect(session.phase, MerchantPhase.shopRequired);
      expect(
        r.requests.where((q) => q.url.path.endsWith('/attempts')).length,
        1,
      );
      expect(r.exchanges.length, 1);
      expect(
        jsonDecode(saved!)['pending']['state'],
        r.exchanges.single['state'],
      );
    },
  );

  test(
    'storage write failures are typed and retry after storage recovers',
    () async {
      final r = Rig();
      final store = SwitchableStore(r.store)..failWrites = true;
      final gateway = MerchantApiAuth(
        r.config,
        api: r.api,
        store: store,
        native: r.native,
        clock: () => r.now,
      );
      await expectLater(
        gateway.authorize(),
        throwsA(
          failureAt(
            MerchantAuthIssue.storageUnavailable,
            MerchantAuthStage.storageWrite,
            'STORAGE_UNAVAILABLE',
          ),
        ),
      );
      expect(r.requests, isEmpty);
      store.failWrites = false;
      expect((await gateway.authorize()).ownerId, 42);
    },
  );

  test(
    'corrupt saved storage is identified without clearing or sending it',
    () async {
      final r = Rig();
      const raw = '{corrupt synthetic stored credentials';
      r.store.values['auth'] = raw;
      await expectLater(
        r.gateway.restore(),
        throwsA(
          failureAt(
            MerchantAuthIssue.storageUnavailable,
            MerchantAuthStage.storageRead,
            'STORAGE_INVALID',
          ),
        ),
      );
      expect(r.store.values['auth'], raw);
      expect(r.requests, isEmpty);
    },
  );

  test('secure storage read failure is distinguished without exposing platform data', () async {
    final r = Rig();
    final session = MerchantSession(
      MerchantApiAuth(
        r.config,
        api: r.api,
        store: ReadFailureStore(),
        native: r.native,
      ),
    );
    addTearDown(session.dispose);
    await session.initialize();
    expect(session.failure, MerchantAuthIssue.storageUnavailable);
    expect(session.diagnostic?.stage, MerchantAuthStage.storageRead);
    expect(session.errorDetails, isNot(contains('private platform')));
    expect(r.requests, isEmpty);
  });

  test(
    'malformed start schema and backend rejection retain their stage',
    () async {
      final r = Rig();
      var badSchema = true;
      intercept(r, (req) async {
        if (req.url.path.endsWith('/attempts')) {
          return badSchema
              ? r.ok({'attemptId': 17})
              : http.Response('<html>rejected</html>', 403);
        }
        return null;
      });
      await expectLater(
        r.gateway.authorize(),
        throwsA(
          failureAt(
            MerchantAuthIssue.invalidResponse,
            MerchantAuthStage.createAttempt,
            'INVALID_RESPONSE',
          ),
        ),
      );
      expect(jsonDecode(r.store.values['auth']!)['pending'], null);
      badSchema = false;
      await expectLater(
        r.gateway.authorize(),
        throwsA(
          failureAt(
            MerchantAuthIssue.rejected,
            MerchantAuthStage.createAttempt,
            'INVALID_RESPONSE',
            status: 403,
          ),
        ),
      );
      expect(r.native.opened, isEmpty);
    },
  );

  test(
    'non-JSON unauthorized identity clears tokens and requires fresh approval',
    () async {
      final r = Rig();
      await r.gateway.authorize();
      intercept(
        r,
        (req) async => req.url.path.endsWith('/session')
            ? http.Response('not authorized', 401)
            : null,
      );
      await expectLater(
        r.gateway.restore(),
        throwsA(
          failureAt(
            MerchantAuthIssue.expired,
            MerchantAuthStage.identity,
            'INVALID_RESPONSE',
            status: 401,
          ),
        ),
      );
      expect(jsonDecode(r.store.values['auth']!)['tokens'], null);
    },
  );

  test('uncertain rotating refresh never restores identity or automatically replays', () async {
    final r = Rig();
    await r.gateway.authorize();
    var refreshes = 0;
    intercept(r, (req) async {
      if (req.url.path.endsWith('/refresh')) {
        refreshes++;
        return http.Response('<html>lost refresh</html>', 503);
      }
      return null;
    });
    r.now = r.now.add(const Duration(minutes: 6));
    await expectLater(
      r.gateway.restore(),
      throwsA(
        failureAt(
          MerchantAuthIssue.serverUnavailable,
          MerchantAuthStage.refresh,
          'INVALID_RESPONSE',
          status: 503,
        ),
      ),
    );
    expect(jsonDecode(r.store.values['auth']!)['refreshing'], true);
    await expectLater(
      r.gateway.authorize(),
      throwsA(
        failureAt(
          MerchantAuthIssue.expired,
          MerchantAuthStage.refresh,
          'REFRESH_UNCERTAIN',
        ),
      ),
    );
    expect(refreshes, 1);
    expect(r.exchanges.length, 1);
  });

  test(
    'late reopen failure after cancellation does not overwrite the session',
    () async {
      final r = Rig()..sendCallback = false;
      final native = DelayedOpenNative();
      final gateway = MerchantApiAuth(
        r.config,
        api: r.api,
        store: r.store,
        native: native,
        clock: () => r.now,
      );
      final session = MerchantSession(gateway);
      addTearDown(session.dispose);
      final starting = session.signIn();
      await r.until(
        () => r.requests.any((q) => q.url.path.endsWith('/status')),
      );
      final reopening = session.reopen();
      await r.until(() => native.opens == 2);
      await session.cancel();
      native.later.completeError(const HandoffFailure('PEER_OPEN_FAILED'));
      await reopening;
      await starting;
      expect(session.failure, null);
      expect(session.diagnostic, null);
      expect(session.phase, MerchantPhase.signedOut);
    },
  );

  test('support reports allow only stage, known code and valid HTTP status', () {
    const diagnostic = MerchantAuthDiagnostic(
      MerchantAuthStage.identity,
      'SECRET_ACCESS_TOKEN_IN_A_SERVER_ERROR',
      httpStatus: 503,
    );
    expect(
      diagnostic.supportText,
      'Kesor Merchant sign-in\nStage: identity\nCode: UNKNOWN_ERROR\nHTTP: 503',
    );
    expect(diagnostic.supportText, isNot(contains('SECRET_ACCESS_TOKEN')));
    expect(
      const MerchantAuthDiagnostic(
        MerchantAuthStage.unknown,
        'OFFLINE',
        httpStatus: 9999,
      ).supportText,
      isNot(contains('HTTP')),
    );
  });

  for (final km in [false, true]) {
    testWidgets(
      '${km ? 'Khmer' : 'English'} failure copies only safe details and clears on cancel',
      (tester) async {
        tester.view.physicalSize = const Size(440, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final prefs = MerchantPreferences()..setLanguage(km ? 'km' : 'en');
        final auth = DiagnosticAuth(
          const MerchantAuthFailure(
            MerchantAuthIssue.appMismatch,
            diagnostic: MerchantAuthDiagnostic(
              MerchantAuthStage.verifyCustomer,
              'PEER_SIGNATURE_MISMATCH',
            ),
          ),
        );
        final session = MerchantSession(auth);
        addTearDown(session.dispose);
        addTearDown(prefs.dispose);
        await session.signIn();
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.pumpWidget(diagnosticApp(session, prefs));
        await tester.pumpAndSettle();
        final copy = find.byKey(const ValueKey('copy-merchant-auth-details'));
        await tester.ensureVisible(copy);
        await tester.tap(copy);
        await tester.pumpAndSettle();
        expect(
          copied,
          'Kesor Merchant sign-in\nStage: verifyCustomer\nCode: PEER_SIGNATURE_MISMATCH',
        );
        expect(
          find.text(km ? 'បានចម្លងព័ត៌មានកំហុស' : 'Error details copied'),
          findsOneWidget,
        );
        expect(
          find.textContaining(km ? 'ដែលត្រូវគ្នា' : 'matching Kesor Bank'),
          findsOneWidget,
        );
        await session.cancel();
        await tester.pumpAndSettle();
        expect(session.diagnostic, null);
        expect(
          find.byKey(const ValueKey('copy-merchant-auth-details')),
          findsNothing,
        );
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
