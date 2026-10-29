import 'dart:async';

import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/core/network/api_client.dart';
import 'package:customer_app/core/network/exact_json.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/accounts/account_gateway.dart';
import 'package:customer_app/features/accounts/accounts_controller.dart';
import 'package:customer_app/features/accounts/creation_store.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:customer_app/shared/money.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

BankAccount account(
  int id, {
  String currency = 'USD',
  String status = 'ACTIVE',
}) => BankAccount(
  id: id,
  number: '${1000000000 + id}',
  type: 'SAVINGS',
  balance: Money.parse('0', currency),
  status: status,
  createdAt: DateTime.utc(2026),
);

class FakeAccounts implements AccountGateway {
  List<BankAccount> data = [];
  final pages = <int>[];
  int opens = 0;
  ApiFailure? listFailure, openFailure;
  Future<BankAccount> Function(String)? onDetail;
  Future<List<RecentPosting>> Function(String)? onRecent;
  Completer<BankAccount>? openGate;
  @override
  Future<List<BankAccount>> list(String token, int page) async {
    pages.add(page);
    if (listFailure != null) throw listFailure!;
    return data.skip(page * 20).take(20).toList();
  }

  @override
  Future<BankAccount> detail(String token, String number) async =>
      onDetail != null
      ? onDetail!(number)
      : data.firstWhere((a) => a.number == number);
  @override
  Future<List<RecentPosting>> recent(String token, String number) async =>
      onRecent != null ? onRecent!(number) : [];
  @override
  Future<BankAccount> open(String token, String type, String currency) async {
    opens++;
    if (openFailure != null) throw openFailure!;
    if (openGate != null) return openGate!.future;
    final result = account(data.length + 1, currency: currency);
    data.add(result);
    return result;
  }
}

class BrokenCreationStore extends MemoryCreationStore {
  bool broken = true;
  @override
  Future<void> setPending(int userId, bool value) async {
    if (broken) throw StateError('Storage unavailable');
    return super.setPending(userId, value);
  }
}

void main() {
  test(
    'JSON monetary lexemes stay exact, including large decimals and exponents',
    () {
      final data = decodeExactJson(
        r'{"balance":9999999999999.99,"amount":1.23e2,"id":12,"text":"balance: 1.25 and \"quotes\""}',
      ) as Map;
      expect(data['id'], 12);
      expect(
        Money.parse(data['balance'], 'USD').formatted,
        'USD 9,999,999,999,999.99',
      );
      expect(Money.parse(data['amount'], 'USD').formatted, 'USD 123.00');
      expect(data['text'], 'balance: 1.25 and "quotes"');
      expect(Money.parse('1234567.00', 'KHR').formatted, 'KHR 1,234,567');
      expect(Money.parse(0, 'USD').formatted, 'USD 0.00');
    },
  );
  test('money rejects floating point, nonfinite, precision loss and range overflow', () {
    for (final value in [
      1.25,
      'NaN',
      '-1',
      '1.001',
      '1e9999',
      '10000000000000',
    ]) {
      expect(() => Money.parse(value, 'USD'), throwsA(isA<ApiFailure>()));
    }
    expect(() => Money.parse('1.01', 'KHR'), throwsA(isA<ApiFailure>()));
    expect(() => Money.parse('1', 'EUR'), throwsA(isA<ApiFailure>()));
  });
  test('malformed JSON remains invalid after lexical preservation', () {
    for (final value in [
      '{"a":01.2}',
      '{"a":1.2.3}',
      '{"a":1e+}',
      '{"a":"bad\n"}',
    ]) {
      expect(() => decodeExactJson(value), throwsFormatException);
    }
  });
  test('gateway preserves envelopes, encodes pagination and sends zero once', () async {
    final requests = <http.Request>[];
    const dto =
        '{"id":1,"accountNumber":"1000000001","accountType":"SAVINGS","currency":"USD","balance":9999999999999.99,"status":"ACTIVE","createdAt":"2026-10-19T12:00:00Z"}';
    final client = ApiClient(
      AppConfig(apiBaseUrl: 'http://localhost:8080/api/v1', environment: 'dev'),
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST') {
          return http.Response(
            '{"success":true,"data":${dto.replaceFirst('9999999999999.99', '0.00')}}',
            201,
          );
        }
        return http.Response('{"success":true,"data":[$dto]}', 200);
      }),
    );
    addTearDown(client.close);
    final gateway = HttpAccountGateway(client);
    final accounts = await gateway.list('token', 3);
    expect(accounts.single.balance.formatted, 'USD 9,999,999,999,999.99');
    expect(requests.single.url.queryParameters, {'page': '3', 'size': '20'});
    expect(requests.single.headers['authorization'], 'Bearer token');
    await gateway.open('token', 'SAVINGS', 'USD');
    expect(requests.length, 2);
    expect(
      requests.last.body,
      '{"accountType":"SAVINGS","currency":"USD","initialDeposit":0}',
    );
  });
  test(
    'posting ownership and SUCCESS status match actual backend contract',
    () {
      final posting = RecentPosting.fromJson({
        'referenceNumber': 'REF',
        'sourceAccountNumber': null,
        'destinationAccountNumber': '1000000001',
        'amount': '10.00',
        'fee': 0,
        'currency': 'USD',
        'transactionType': 'DEPOSIT',
        'status': 'SUCCESS',
        'createdAt': '2026-10-19T12:00:00Z',
      }, '1000000001');
      expect(posting.direction('1000000001'), 'Deposit');
      expect(
        () => RecentPosting.fromJson({
          'referenceNumber': 'REF',
          'sourceAccountNumber': null,
          'destinationAccountNumber': 'other',
          'amount': '10',
          'fee': 0,
          'currency': 'USD',
          'transactionType': 'DEPOSIT',
          'status': 'SUCCESS',
          'createdAt': '2026-10-19T12:00:00Z',
        }, '1000000001'),
        throwsA(isA<ApiFailure>()),
      );
    },
  );

  group('account state and session safety', () {
    late FakeGateway auth;
    late SessionController session;
    late FakeAccounts gateway;
    late MemoryCreationStore store;
    late AccountsController model;
    setUp(() async {
      auth = FakeGateway()..expiresInMs = 600000;
      session = SessionController(auth, MemorySessionVault());
      await session.initialize();
      await session.begin(
        email: 'customer@example.test',
        password: 'Password1!',
        register: false,
      );
      await session.verifyCode('123456');
      gateway = FakeAccounts();
      store = MemoryCreationStore();
      model = AccountsController(session, gateway, store);
    });
    tearDown(() {
      model.dispose();
      session.dispose();
    });
    test(
      'empty customer, paginated list, selection beyond first page',
      () async {
        await model.initialize();
        expect(model.accounts, isEmpty);
        expect(model.selected, null);
        gateway.data = List.generate(25, (i) => account(i + 1));
        await model.refresh();
        await model.loadMore();
        expect(model.accounts.length, 25);
        expect(model.hasMore, false);
        await model.select(model.accounts.last);
        await model.refresh();
        expect(model.selected!.number, account(25).number);
        await model.loadMore();
        expect(model.accounts.map((a) => a.number).toSet().length, 25);
      },
    );
    test(
      'explicit opening selects confirmed zero account and does not repeat',
      () async {
        await model.initialize();
        expect(await model.open('SAVINGS', 'USD'), true);
        expect(model.selected!.balance.formatted, 'USD 0.00');
        expect(gateway.opens, 1);
        expect(await store.pending(1), false);
        await model.refresh();
        expect(gateway.opens, 1);
      },
    );
    test('double submission is blocked while first POST is pending', () async {
      await model.initialize();
      gateway.openGate = Completer();
      final first = model.open('SAVINGS', 'USD');
      await Future<void>.delayed(Duration.zero);
      expect(await store.pending(1), true);
      expect(await model.open('SAVINGS', 'USD'), false);
      gateway.data = [account(1)];
      gateway.openGate!.complete(account(1));
      await first;
      expect(gateway.opens, 1);
    });
    test('uncertain creation persists across controller recreation and needs new decision', () async {
      await model.initialize();
      gateway.openFailure = const ApiFailure('TIMEOUT', 'Timed out');
      await model.open('SAVINGS', 'USD');
      expect(model.uncertain, true);
      expect(await store.pending(1), true);
      expect(model.checkedAfterUncertainty, true);
      model.dispose();
      model = AccountsController(session, gateway, store);
      await model.initialize();
      expect(model.uncertain, true);
      expect(await model.open('SAVINGS', 'USD'), false);
      expect(gateway.opens, 1);
      await model.allowNewAccount();
      expect(await store.pending(1), false);
      gateway.openFailure = null;
      expect(await model.open('SAVINGS', 'USD'), true);
      expect(gateway.opens, 2);
    });
    test(
      'definite validation rejection unlocks manual corrected submission',
      () async {
        await model.initialize();
        gateway.openFailure = const ApiFailure(
          'VALIDATION_FAILED',
          'Invalid',
          status: 400,
        );
        await model.open('SAVINGS', 'USD');
        expect(model.uncertain, false);
        expect(await store.pending(1), false);
        expect(gateway.opens, 1);
      },
    );
    test('failed marker write prevents sending a POST', () async {
      model.dispose();
      final broken = BrokenCreationStore();
      model = AccountsController(session, gateway, broken);
      await model.initialize();
      await model.open('SAVINGS', 'USD');
      expect(gateway.opens, 0);
      expect(model.storageError, isNotNull);
    });
    test('late selection response cannot replace another account', () async {
      gateway.data = [account(1), account(2)];
      await model.initialize();
      final late = Completer<BankAccount>();
      gateway.onDetail = (number) async =>
          number == account(1).number ? late.future : account(2);
      final pending = model.select(account(1));
      await model.select(account(2));
      late.complete(account(1));
      await pending;
      expect(model.selected!.number, account(2).number);
    });
    test(
      'late activity cannot replace the newly selected account activity',
      () async {
        RecentPosting posting(int id) => RecentPosting(
          reference: 'REF-$id',
          source: null,
          destination: account(id).number,
          amount: Money.parse('10', 'USD'),
          fee: Money.parse('0', 'USD'),
          type: 'DEPOSIT',
          status: 'SUCCESS',
          createdAt: DateTime.utc(2026),
        );
        gateway.data = [account(1), account(2)];
        await model.initialize();
        final delayed = Completer<List<RecentPosting>>();
        gateway.onRecent = (number) => number == account(1).number
            ? delayed.future
            : Future.value([posting(2)]);
        final old = model.select(account(1));
        await model.select(account(2));
        delayed.complete([posting(1)]);
        await old;
        expect(model.activity.single.destination, account(2).number);
      },
    );
    test('late rejected creation from an ended session cannot erase a new safety marker', () async {
      await model.initialize();
      gateway.openGate = Completer<BankAccount>();
      final opening = model.open('SAVINGS', 'USD');
      await Future<void>.delayed(Duration.zero);
      await session.signOut();
      await store.setPending(1, true);
      gateway.openGate!.completeError(
        const ApiFailure('VALIDATION_FAILED', 'Rejected', status: 400),
      );
      await opening;
      expect(await store.pending(1), true);
      expect(model.accounts, isEmpty);
    });
    test(
      'logout clears data immediately and late responses cannot restore it',
      () async {
        gateway.data = [account(1)];
        await model.initialize();
        final late = Completer<BankAccount>();
        gateway.onDetail = (_) => late.future;
        final pending = model.select(account(1));
        final logout = session.signOut();
        expect(model.accounts, isEmpty);
        expect(model.selected, null);
        expect(model.activity, isEmpty);
        late.complete(account(1));
        await Future.wait([pending, logout]);
        expect(model.accounts, isEmpty);
        expect(model.selected, null);
      },
    );
    test(
      'failed refresh retains known data with failure and prior timestamp',
      () async {
        gateway.data = [account(1, status: 'FROZEN')];
        await model.initialize();
        final timestamp = model.accountsUpdatedAt;
        gateway.listFailure = const ApiFailure('OFFLINE', 'Offline');
        await model.refresh();
        expect(model.selected!.status, 'FROZEN');
        expect(model.listError, isNotNull);
        expect(model.accountsUpdatedAt, timestamp);
      },
    );
    test('uncertainty is isolated by user identity', () async {
      await store.setPending(2, true);
      await model.initialize();
      expect(model.uncertain, false);
    });
    test('mutation TOKEN_INVALID is never replayed', () async {
      var calls = 0;
      await expectLater(
        session.authorizedMutation((token) async {
          calls++;
          throw const ApiFailure('TOKEN_INVALID', 'Expired', status: 401);
        }),
        throwsA(isA<ApiFailure>()),
      );
      expect(calls, 1);
      expect(auth.refreshCalls, 0);
      expect(session.phase, SessionPhase.signedOut);
    });
    test('concurrent feature reads share one renewal and retry once', () async {
      final rejected = [Completer<String>(), Completer<String>()];
      var oldCalls = 0;
      Future<String> read(String token) async =>
          token == 'access-login' ? rejected[oldCalls++].future : 'ok';
      final first = session.authorizedRead(read);
      final second = session.authorizedRead(read);
      rejected[0].completeError(
        const ApiFailure('TOKEN_INVALID', 'Expired', status: 401),
      );
      expect(await first, 'ok');
      rejected[1].completeError(
        const ApiFailure('TOKEN_INVALID', 'Expired', status: 401),
      );
      expect(await second, 'ok');
      expect(auth.refreshCalls, 1);
    });
  });
}
