import 'dart:async';
import 'dart:convert';

import 'package:customer_app/app/banking_app.dart';
import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/core/network/api_client.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/accounts/account_gateway.dart';
import 'package:customer_app/features/accounts/creation_store.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:customer_app/features/home/home_controller.dart';
import 'package:customer_app/features/home/home_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

Map<String, Object?> accountJson(
  int id, {
  String currency = 'USD',
  String balance = '9999999999999.99',
}) => {
  'id': id,
  'accountNumber': '${1000000000 + id}',
  'accountType': 'SAVINGS',
  'balance': balance,
  'currency': currency,
  'status': 'ACTIVE',
  'createdAt': '2026-10-01T00:00:00Z',
};
Map<String, Object?> postingJson(
  String ref,
  String? source,
  String? destination, {
  String currency = 'USD',
  String amount = '10.25',
  String date = '2026-10-29T10:00:00Z',
}) => {
  'referenceNumber': ref,
  'sourceAccountNumber': source,
  'destinationAccountNumber': destination,
  'amount': amount,
  'fee': '0',
  'currency': currency,
  'transactionType': 'TRANSFER',
  'status': 'SUCCESS',
  'createdAt': date,
  'remark': null,
};
http.Response ok(Object? data) =>
    http.Response(jsonEncode({'success': true, 'data': data}), 200);
AppConfig get config =>
    AppConfig(apiBaseUrl: 'http://localhost:8080/api/v1', environment: 'dev');
Future<SessionController> signedIn() async {
  final session = SessionController(
    FakeGateway()..expiresInMs = 600000,
    MemorySessionVault(),
  );
  await session.initialize();
  await session.begin(
    email: 'customer@example.test',
    password: 'Password1!',
    register: false,
  );
  await session.verifyCode('123456');
  return session;
}

class ControlledHomeGateway implements HomeGateway {
  final List<Completer<HomeSnapshot>> requests = [];
  @override
  Future<HomeSnapshot> load(String token) {
    final request = Completer<HomeSnapshot>();
    requests.add(request);
    return request.future;
  }
}

void main() {
  test('reads every owned account page and recent history, preserves exact money, deduplicates internal transfers', () async {
    final requests = <http.Request>[];
    final client = ApiClient(
      config,
      client: MockClient((r) async {
        requests.add(r);
        expect(r.method, 'GET');
        expect(r.headers['Authorization'], 'Bearer home-token');
        if (r.url.path.endsWith('/accounts/me')) {
          expect(r.url.queryParameters['size'], '20');
          return ok(
            r.url.queryParameters['page'] == '0'
                ? List.generate(20, (i) => accountJson(i + 1))
                : [accountJson(21, currency: 'KHR', balance: '2000')],
          );
        }
        expect(r.url.queryParameters, {'page': '0', 'size': '5'});
        final number = r.url.pathSegments.last;
        final internal = postingJson(
          'INTERNAL',
          '1000000001',
          '1000000002',
          date: '2026-10-29T09:00:00Z',
        );
        return ok({
          'content': number == '1000000001'
              ? [postingJson('USD-IN', '9000000001', number), internal]
              : number == '1000000002'
              ? [internal]
              : number == '1000000021'
              ? [
                  postingJson(
                    'KHR-OUT',
                    number,
                    '9000000002',
                    currency: 'KHR',
                    amount: '100000',
                    date: '2026-10-28T10:00:00Z',
                  ),
                ]
              : [],
        });
      }),
    );
    addTearDown(client.close);
    final snapshot = await AccountHomeGateway(HttpAccountGateway(client))
        .load('home-token');
    expect(snapshot.accounts.length, 21);
    expect(
      requests.where((r) => r.url.path.endsWith('/accounts/me')).length,
      2,
    );
    expect(
      requests
          .where((r) => r.url.path.contains('/transactions/account/'))
          .length,
      21,
    );
    expect(snapshot.postings.map((p) => p.reference), [
      'USD-IN',
      'INTERNAL',
      'KHR-OUT',
    ]);
    final ui = snapshot.presentation(
      const Locale('en'),
      now: DateTime.utc(2026, 10, 29, 12),
    );
    expect(ui.usdBalance, r'$199999999999999.80');
    expect(ui.khrBalance, '2,000');
    expect(ui.transactions[0].incoming, isTrue);
    expect(ui.transactions[1].internal, isTrue);
    expect(ui.transactions[1].amount, '↔ \$10.25');
    expect(ui.transactions[2].amount, '-100000 ៛');
    expect(ui.recipients.map((r) => r.name), ['9000000001', '9000000002']);
  });

  test('failed history rejects an incomplete Home snapshot; no sample-data fallback', () async {
    final client = ApiClient(
      config,
      client: MockClient((r) async {
        if (r.url.path.endsWith('/accounts/me')) return ok([accountJson(1)]);
        return http.Response('{"success":false,"error":"ACCESS_DENIED"}', 403);
      }),
    );
    addTearDown(client.close);
    await expectLater(
      AccountHomeGateway(HttpAccountGateway(client)).load('token'),
      throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 403)),
    );
  });

  test('empty authenticated account list is a real zero balance', () async {
    final client = ApiClient(config, client: MockClient((r) async => ok([])));
    addTearDown(client.close);
    final snapshot = await AccountHomeGateway(HttpAccountGateway(client))
        .load('token');
    final ui = snapshot.presentation(const Locale('en'));
    expect(ui.usdBalance, r'$0.00');
    expect(ui.khrBalance, '0');
    expect(ui.transactions, isEmpty);
    expect(ui.recipients, isEmpty);
  });

  test(
    'newer refresh wins and sign-out invalidates a pending private response',
    () async {
      final session = await signedIn();
      addTearDown(session.dispose);
      final gateway = ControlledHomeGateway();
      final home = HomeController(session, gateway);
      addTearDown(home.dispose);
      final first = home.refresh();
      final second = home.refresh();
      await Future<void>.delayed(Duration.zero);
      final newer = HomeSnapshot([BankAccount.fromJson(accountJson(2))], []);
      gateway.requests[1].complete(newer);
      await second;
      gateway.requests[0].complete(const HomeSnapshot([], []));
      await first;
      expect(home.snapshot, same(newer));
      final pending = home.refresh();
      await Future<void>.delayed(Duration.zero);
      await session.signOut();
      gateway.requests[2].complete(newer);
      await pending;
      expect(home.snapshot, isNull);
      expect(home.loading, isFalse);
    },
  );

  test('failed refresh retains the last snapshot and explicitly reports stale data', () async {
    final session = await signedIn();
    addTearDown(session.dispose);
    final gateway = ControlledHomeGateway();
    final home = HomeController(session, gateway);
    addTearDown(home.dispose);
    final first = home.refresh();
    await Future<void>.delayed(Duration.zero);
    final loaded = HomeSnapshot([BankAccount.fromJson(accountJson(1))], []);
    gateway.requests[0].complete(loaded);
    await first;
    final retry = home.refresh();
    await Future<void>.delayed(Duration.zero);
    gateway.requests[1].completeError(const ApiFailure('OFFLINE', 'Offline'));
    await retry;
    expect(home.snapshot, same(loaded));
    expect(home.error?.code, 'OFFLINE');
  });

  testWidgets(
    'API mode renders authenticated Home data and other tabs are label-only placeholders',
    (tester) async {
      final session = await signedIn();
      addTearDown(session.dispose);
      final requests = <String>[];
      final accounts = [
        accountJson(1, balance: '168.25'),
        accountJson(2, currency: 'KHR', balance: '2500'),
      ];
      final client = ApiClient(
        config,
        client: MockClient((r) async {
          requests.add(r.url.path);
          expect(r.headers['Authorization'], 'Bearer access-login');
          if (r.url.path.endsWith('/accounts/me')) return ok(accounts);
          if (r.url.path.contains('/transactions/account/')) {
            return ok({'content': []});
          }
          return ok(
            accounts.firstWhere(
              (a) => a['accountNumber'] == r.url.pathSegments.last,
            ),
          );
        }),
      );
      addTearDown(client.close);
      await tester.pumpWidget(
        BankingApp(
          session: session,
          config: config,
          accountGateway: HttpAccountGateway(client),
          creationStore: MemoryCreationStore(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('home-usd-balance')))
            .data,
        r'$168.25',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('home-khr-balance')))
            .textSpan!
            .toPlainText(),
        '2,500៛',
      );
      expect(requests, contains('/api/v1/transactions/account/1000000002'));
      expect(find.textContaining('DEMO'), findsNothing);
      await tester.tap(find.byTooltip('Hide balance'));
      await tester.pumpAndSettle();
      for (final i in [1, 2]) {
        await tester.tap(find.byKey(ValueKey('bottom-tab-$i')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(find.byKey(ValueKey('placeholder-tab-$i'))).data,
          i == 1 ? 'Analytics' : 'Settings',
        );
        expect(find.byKey(const ValueKey('home-usd-balance')), findsNothing);
      }
      await tester.tap(find.byKey(const ValueKey('bottom-tab-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-usd-balance')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('home-usd-balance')))
            .data,
        r'$••••',
      );
      await tester.tap(find.byTooltip('Show balance'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('home-usd-balance')))
            .data,
        r'$168.25',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
