import 'dart:async';
import 'dart:convert';

import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/core/network/api_client.dart';
import 'package:customer_app/features/assistant/assistant_controller.dart';
import 'package:customer_app/features/assistant/assistant_gateway.dart';
import 'package:customer_app/features/assistant/assistant_models.dart';
import 'package:customer_app/features/assistant/assistant_store.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'qr_pairs_test.dart' show signedSession;
import 'support/assistant_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('assistant recovery and ownership', () {
    late SessionController session;
    late FakeAssistant api;
    late AssistantPendingStore store;
    late AssistantController model;
    setUp(() async {
      session = await signedSession();
      api = FakeAssistant();
      store = AssistantPendingStore();
      model = AssistantController(session, api, store);
      await model.initialize();
    });
    tearDown(() {
      model.dispose();
      session.dispose();
    });
    test('explicit send creates and records a verified result without touching transfer storage', () async {
      await model.send('Show my balances', 'en');
      expect(api.creates, 1);
      expect(api.requests, hasLength(1));
      expect(
        model.messages.single.answer.cards.first.fields.first.value,
        'USD 190.00',
      );
      expect(await store.read(1), null);
      expect(model.pending, null);
    });
    test(
      'timeout recovery after controller recreation only reads original result',
      () async {
        api.loseSendResponse = true;
        api.statusFailure = const ApiFailure('OFFLINE', 'Offline');
        await model.send('Show my balances', 'en');
        final saved = (await store.read(1))!;
        expect(saved.phase, 'MESSAGE');
        expect(api.requests, hasLength(1));
        model.dispose();
        api.statusFailure = null;
        model = AssistantController(session, api, store);
        await model.initialize();
        expect(api.requests, hasLength(1));
        expect(model.lastTurn!.status, 'COMPLETED');
        expect(await store.read(1), null);
      },
    );
    test(
      'unknown-result explicit retry keeps the same immutable key and body',
      () async {
        api.loseSendResponse = true;
        api.statusFailure = const ApiFailure(
          'RESOURCE_NOT_FOUND',
          'Unavailable',
          status: 404,
        );
        await model.send('Show my balances', 'en');
        final original = api.requests.single;
        await model.retry();
        expect(api.requests.last.key, original.key);
        expect(api.requests.last.body, original.body);
        expect(api.turns, hasLength(1));
        expect(model.messages, hasLength(1));
      },
    );
    test('lost conversation response is recovered by GET without sending the saved question', () async {
      api.loseCreateResponse = true;
      await model.send('Show my balances', 'en');
      expect(api.requests, isEmpty);
      final original = (await store.read(1))!;
      expect(original.phase, 'CREATE');
      model.dispose();
      model = AssistantController(session, api, store);
      await model.initialize();
      expect(api.creates, 1);
      expect(api.creationReads, 1);
      expect(api.requests, isEmpty);
      expect(model.pending!.phase, 'MESSAGE');
      await model.retry();
      expect(api.requests, hasLength(1));
      expect(api.creates, 1);
    });
    test(
      'confirmed provider failure requires explicit retry with a new key',
      () async {
        api.sendFailure = const ApiFailure(
          'AI_UNAVAILABLE',
          'Unavailable',
          status: 503,
        );
        await model.send('Show my balances', 'en');
        final key = api.requests.single.key;
        expect(model.pending!.failed, true);
        expect((await store.read(1))!.failed, true);
        api.sendFailure = null;
        await model.retry();
        expect(api.requests.last.key, isNot(key));
        expect(model.lastTurn!.status, 'COMPLETED');
      },
    );
    test(
      'sensitive input and disabled configuration send no requests',
      () async {
        await model.send('my PIN is 0012', 'en');
        expect(model.error!.code, 'AI_SENSITIVE_INPUT');
        expect(await store.read(1), null);
        expect(api.requests, isEmpty);
        api.enabled = false;
        await model.initialize();
        await model.send('balances', 'en');
        expect(api.requests, isEmpty);
      },
    );
    test('logout during a request ignores the late response and preserves recovery record', () async {
      api.sendGate = Completer<void>();
      final sending = model.send('Show my balances', 'en');
      for (var i = 0; i < 20 && api.requests.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(api.requests, hasLength(1));
      await session.signOut();
      api.sendGate!.complete();
      await sending;
      expect(model.messages, isEmpty);
      expect(model.lastTurn, null);
      expect(model.pending, null);
      expect(await store.read(1), isNotNull);
    });
    test('navigation stops UI updates; returning re-reads the journal and never resends', () async {
      model.setVisible(true);
      api.sendGate = Completer<void>();
      final sending = model.send('balances', 'en');
      for (var i = 0; i < 20 && api.requests.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      model.setVisible(false);
      api.sendGate!.complete();
      await sending;
      expect(model.lastTurn, null);
      model.setVisible(true);
      for (var i = 0; i < 30 && model.busy; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(api.requests, hasLength(1));
      expect(model.lastTurn!.status, 'COMPLETED');
      model.setVisible(false);
    });
  });
  group('encrypted pending record', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));
    test(
      'persists across stores, isolates API/users and blocks competing claims',
      () async {
        final a = AssistantPendingStore(namespace: 'api|dev'),
            b = AssistantPendingStore(namespace: 'api|dev');
        final record = AiPending.create('balances', 'en');
        final results = await Future.wait([
          a.claim(1, record).then((_) => true, onError: (_) => false),
          b
              .claim(1, AiPending.create('other', 'en'))
              .then((_) => true, onError: (_) => false),
        ]);
        expect(results.where((v) => v), hasLength(1));
        expect((await b.read(1))!.message, 'balances');
        expect(await b.read(2), null);
        expect(await AssistantPendingStore(namespace: 'other').read(1), null);
        await a.replace(1, record.key, record.forMessage(aiConversationId));
        expect((await b.read(1))!.conversation, aiConversationId);
      },
    );
    test('corrupt records fail closed without overwriting', () async {
      final store = AssistantPendingStore(namespace: 'corrupt');
      await store.claim(1, AiPending.create('balances', 'en'));
      const storage = FlutterSecureStorage();
      final key = (await storage.readAll()).keys.single;
      await storage.write(key: key, value: '{bad');
      await expectLater(store.read(1), throwsA(isA<ApiFailure>()));
      await expectLater(
        store.claim(1, AiPending.create('next', 'en')),
        throwsA(isA<ApiFailure>()),
      );
      expect(await storage.read(key: key), '{bad');
    });
    test(
      'replacement cannot change the saved question under its original key',
      () async {
        final store = AssistantPendingStore();
        final old = AiPending.create(
          'balances',
          'en',
        ).forMessage(aiConversationId);
        await store.claim(1, old);
        final changed = AiPending(
          phase: old.phase,
          key: old.key,
          message: 'changed',
          locale: old.locale,
          createdAt: old.createdAt,
          conversation: old.conversation,
          failed: true,
        );
        await expectLater(
          store.replace(1, old.key, changed),
          throwsA(isA<ApiFailure>()),
        );
        expect((await store.read(1))!.message, 'balances');
      },
    );
  });
  test('HTTP gateway uses the envelope, bearer token and immutable idempotency key', () async {
    final record = AiPending.create(
      'balances',
      'en',
    ).forMessage(aiConversationId);
    late http.Request captured;
    final client = ApiClient(
      AppConfig(apiBaseUrl: 'http://localhost:8080/api/v1', environment: 'dev'),
      timeout: const Duration(seconds: 35),
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'requestId': 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
              'status': 'PENDING',
              'answer': null,
              'errorCode': null,
            },
          }),
          202,
        );
      }),
    );
    final gateway = HttpAssistantGateway(client);
    expect((await gateway.send('test-access', record)).status, 'PENDING');
    expect(captured.headers['Authorization'], 'Bearer test-access');
    expect(captured.headers['Idempotency-Key'], record.key);
    expect(jsonDecode(captured.body), record.body);
    expect(client.timeout, const Duration(seconds: 35));
    client.close();
  });
  test(
    'creation recovery uses GET and the same conversation page envelope',
    () async {
      final config = AppConfig(
        apiBaseUrl: 'http://localhost:8080/api/v1',
        environment: 'dev',
      );
      final client = ApiClient(
        config,
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.queryParameters['requestKey'], 'creation-key');
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'items': [
                  {
                    'id': aiConversationId,
                    'title': 'New conversation',
                    'createdAt': '2026-10-30T07:00:00Z',
                    'updatedAt': '2026-10-30T07:00:00Z',
                  },
                ],
                'nextCursor': null,
              },
            }),
            200,
          );
        }),
      );
      expect(
        (await HttpAssistantGateway(
          client,
        ).recoverCreation('token', 'creation-key')).id,
        aiConversationId,
      );
      client.close();
    },
  );
  test('unavailable preview gateway returns a typed failure instead of fake banking answers', () async {
    final gateway = UnavailableAssistantGateway();
    expect(await gateway.available('token'), false);
    await expectLater(
      gateway.conversations('token'),
      throwsA(isA<ApiFailure>()),
    );
  });
  test('untrusted response cannot introduce payment or arbitrary navigation actions', () {
    for (final action in [
      {'type': 'SEND_PAYMENT'},
      {'type': 'HELP_SCREEN', 'value': 'https://bad.example'},
      {'type': 'ACCOUNT', 'accountNumber': '../other'},
    ]) {
      expect(() => AiAction.fromJson(action), throwsA(isA<ApiFailure>()));
    }
    expect(
      () => AiTurn.fromJson({
        'requestId': 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
        'status': 'COMPLETED',
      }),
      throwsA(isA<ApiFailure>()),
    );
  });
  test('answer mode is optional, limited to known values and drives the general-guidance flag', () {
    Map<String, Object?> json([Object? mode]) => {
      'reply': 'Text',
      'cards': <Object>[],
      'asOf': '2026-11-05T01:00:00Z',
      'explanationStatus': 'AI',
      'mode': ?mode,
    };
    expect(AiAnswer.fromJson(json()).mode, isNull);
    expect(AiAnswer.fromJson(json()).hasGeneralGuidance, isFalse);
    expect(AiAnswer.fromJson(json('GENERAL')).hasGeneralGuidance, isTrue);
    expect(AiAnswer.fromJson(json('MIXED')).hasGeneralGuidance, isTrue);
    expect(AiAnswer.fromJson(json('ACCOUNT')).hasGeneralGuidance, isFalse);
    expect(() => AiAnswer.fromJson(json('ADVICE')), throwsA(isA<ApiFailure>()));
    expect(() => AiAnswer.fromJson(json(5)), throwsA(isA<ApiFailure>()));
  });
}
