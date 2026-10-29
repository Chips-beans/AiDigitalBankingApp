import 'dart:async';
import 'dart:convert';

import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/core/network/api_client.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/accounts/account_gateway.dart';
import 'package:customer_app/features/accounts/accounts_controller.dart';
import 'package:customer_app/features/accounts/creation_store.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:customer_app/features/transactions/transaction_gateway.dart';
import 'package:customer_app/features/transactions/transfer_controller.dart';
import 'package:customer_app/features/transactions/history_controller.dart';
import 'package:customer_app/features/transactions/transfer_models.dart';
import 'package:customer_app/features/transactions/transfer_store.dart';
import 'package:customer_app/shared/money.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'accounts_test.dart' show FakeAccounts;
import 'support/fakes.dart';

BankAccount funded(
  int id, {
  String currency = 'USD',
  String balance = '25.50',
  String status = 'ACTIVE',
}) => BankAccount(
  id: id,
  number: '${1000000000 + id}',
  type: 'SAVINGS',
  balance: Money.parse(balance, currency),
  status: status,
  createdAt: DateTime.utc(2026),
);

RecentPosting posting(SavedTransfer record) => RecentPosting(
  reference: 'TXN-${record.key}',
  source: record.draft.source,
  destination: record.draft.destination,
  amount: record.draft.amount,
  fee: Money.parse('0', record.draft.amount.currency),
  type: 'TRANSFER',
  status: 'SUCCESS',
  remark: record.draft.remark,
  createdAt: DateTime.utc(2026),
);

class FakeTransactions implements TransactionGateway {
  final List<SavedTransfer> requests = [];
  final Map<String, RecentPosting> committed = {};
  bool loseResponse = false;
  ApiFailure? failure;
  Completer<void>? gate;
  List<RecentPosting> historyItems = [];
  Future<PostingPage> Function(String, int)? onHistory;
  Future<RecentPosting> Function(String, String)? onDetail;
  @override
  Future<RecentPosting> transfer(String token, SavedTransfer operation) async {
    requests.add(operation);
    await gate?.future;
    if (failure != null) throw failure!;
    final result = committed.putIfAbsent(
      operation.key,
      () => posting(operation),
    );
    if (loseResponse) {
      loseResponse = false;
      throw const ApiFailure('TIMEOUT', 'Timed out');
    }
    return result;
  }

  @override
  Future<PostingPage> history(String token, String account, int page) async =>
      onHistory != null
      ? onHistory!(account, page)
      : PostingPage(
          historyItems.skip(page * 20).take(20).toList(),
          page,
          (page + 1) * 20 >= historyItems.length,
          historyItems.length,
        );
  @override
  Future<RecentPosting> detail(
    String token,
    String account,
    String reference,
  ) async => onDetail != null
      ? onDetail!(account, reference)
      : committed.values.firstWhere((p) => p.reference == reference);
}

class BrokenTransferStore extends MemoryTransferStore {
  bool failClaim = false, failResolve = false;
  @override
  Future<void> claim(int user, SavedTransfer record) async {
    if (failClaim) throw StateError('Unavailable');
    return super.claim(user, record);
  }

  @override
  Future<void> resolve(int user, SavedTransfer record) async {
    if (failResolve) throw StateError('Unavailable');
    return super.resolve(user, record);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('exact transfer entry rejects exponent, zero, mismatch, own destination and precision', () {
    final source = funded(1);
    expect(
      TransferDraft.validate(
        source,
        funded(2).number,
        '1.20',
        ' hello ',
      ).amount.decimal,
      '1.20',
    );
    for (final value in ['0', '1e1', '-1', '1.001', '1,000', '26']) {
      expect(
        () => TransferDraft.validate(source, funded(2).number, value, ''),
        throwsA(isA<ApiFailure>()),
      );
    }
    expect(
      () => TransferDraft.validate(source, source.number, '1', ''),
      throwsA(isA<ApiFailure>()),
    );
    expect(
      () => TransferDraft.validate(
        funded(1, status: 'CLOSED'),
        funded(2).number,
        '1',
        '',
      ),
      throwsA(isA<ApiFailure>()),
    );
    expect(
      () => TransferDraft.validate(
        funded(1, currency: 'KHR', balance: '100'),
        funded(2).number,
        '1.2',
        '',
      ),
      throwsA(isA<ApiFailure>()),
    );
  });
  test('secure record preserves immutable payload, scopes users, and refuses unresolved dismissal', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = SecureTransferStore('test|api');
    final record = SavedTransfer.confirmed(
      TransferDraft.validate(funded(1), funded(2).number, '5.00', 'memo'),
    );
    await store.claim(1, record);
    final restored = (await SecureTransferStore('test|api').read(1))!;
    expect(restored.key, record.key);
    expect(restored.draft.payload, record.draft.payload);
    expect(await store.read(2), null);
    expect(await SecureTransferStore('other|api').read(1), null);
    await expectLater(store.dismiss(1, record.key), throwsA(isA<ApiFailure>()));
    await expectLater(
      SecureTransferStore('test|api').claim(1, record),
      throwsA(isA<ApiFailure>()),
    );
    await store.resolve(1, record.resolve(reference: 'TXN-1'));
    expect((await store.read(1))!.outcome, 'success');
    await store.dismiss(1, record.key);
    expect(await store.read(1), null);
  });
  test(
    'corrupt persisted journal fails closed without overwriting it',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final record = SavedTransfer.confirmed(
        TransferDraft.validate(funded(1), funded(2).number, '5', ''),
      );
      final store = SecureTransferStore('corrupt');
      await store.claim(1, record);
      final values = await const FlutterSecureStorage().readAll();
      final key = values.keys.single;
      await const FlutterSecureStorage().write(key: key, value: '{invalid');
      await expectLater(store.read(1), throwsA(isA<ApiFailure>()));
      await expectLater(store.claim(1, record), throwsA(isA<ApiFailure>()));
      expect(await const FlutterSecureStorage().read(key: key), '{invalid');
    },
  );
  test('competing secure claims reserve exactly one transfer', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final a = SecureTransferStore('race'), b = SecureTransferStore('race');
    final record = SavedTransfer.confirmed(
      TransferDraft.validate(funded(1), funded(2).number, '5', ''),
    );
    final results = await Future.wait([
      a.claim(1, record).then((_) => true, onError: (_) => false),
      b
          .claim(1, SavedTransfer.confirmed(record.draft))
          .then((_) => true, onError: (_) => false),
    ]);
    expect(results.where((r) => r), hasLength(1));
  });
  test('HTTP transfer sends canonical strings, one stable key, and maps actual page envelopes', () async {
    final record = SavedTransfer.confirmed(
      TransferDraft.validate(funded(1), funded(2).number, '5.00', 'memo'),
    );
    final calls = <http.Request>[];
    final data = {
      'referenceNumber': 'TXN-1',
      'sourceAccountNumber': record.draft.source,
      'destinationAccountNumber': record.draft.destination,
      'amount': '5.00',
      'fee': 0,
      'currency': 'USD',
      'transactionType': 'TRANSFER',
      'status': 'SUCCESS',
      'remark': 'memo',
      'createdAt': '2026-10-19T12:00:00Z',
    };
    final client = ApiClient(
      AppConfig(apiBaseUrl: 'http://localhost:8080/api/v1', environment: 'dev'),
      client: MockClient((r) async {
        calls.add(r);
        final payload = r.url.path.endsWith('/account/${record.draft.source}')
            ? {
                'content': [data],
                'pageNo': 1,
                'pageSize': 20,
                'last': true,
                'totalElements': 21,
                'totalPages': 2,
              }
            : data;
        return http.Response(
          jsonEncode({'success': true, 'data': payload}),
          200,
        );
      }),
    );
    addTearDown(client.close);
    final gateway = HttpTransactionGateway(client);
    expect((await gateway.transfer('token', record)).status, 'SUCCESS');
    expect(calls.single.headers['idempotency-key'], record.key);
    expect(jsonDecode(calls.single.body), record.draft.payload);
    expect((await gateway.history('token', record.draft.source, 1)).last, true);
    expect(calls.last.url.queryParameters, {'page': '1', 'size': '20'});
    await gateway.detail('token', record.draft.source, 'TXN-1');
    await expectLater(
      gateway.detail('token', funded(3).number, 'TXN-1'),
      throwsA(isA<ApiFailure>()),
    );
  });

  group('transfer lifecycle', () {
    late FakeGateway auth;
    late SessionController session;
    late FakeTransactions gateway;
    late BrokenTransferStore store;
    late TransferController controller;
    setUp(() async {
      auth = FakeGateway()..expiresInMs = 600000;
      session = SessionController(auth, MemorySessionVault());
      await session.initialize();
      await session.begin(
        email: 'qa@example.test',
        password: 'Password1!',
        register: false,
      );
      await session.verifyCode('123456');
      gateway = FakeTransactions();
      store = BrokenTransferStore();
      controller = TransferController(session, gateway, store);
      await controller.initialize();
    });
    tearDown(() {
      controller.dispose();
      session.dispose();
    });
    void prepare() => expect(
      controller.prepare(funded(1), funded(2).number, '5', 'memo'),
      true,
    );
    test('review sends nothing; duplicate taps send one request; confirmed journal can be dismissed', () async {
      prepare();
      expect(gateway.requests, isEmpty);
      gateway.gate = Completer();
      final sending = controller.confirm();
      await Future<void>.delayed(Duration.zero);
      await controller.confirm();
      expect(gateway.requests.length, 1);
      gateway.gate!.complete();
      await sending;
      expect(controller.saved!.outcome, 'success');
      expect((await store.read(1))!.outcome, 'success');
      await controller.dismiss();
      expect(await store.read(1), null);
    });
    test('lost committed response restores without POST; explicit same-key retry posts once', () async {
      prepare();
      gateway.loseResponse = true;
      await controller.confirm();
      final original = gateway.requests.single;
      expect(controller.saved!.unresolved, true);
      expect(gateway.committed.length, 1);
      controller.dispose();
      controller = TransferController(session, gateway, store);
      await controller.initialize();
      expect(gateway.requests.length, 1);
      expect(controller.prepare(funded(1), funded(2).number, '1', ''), false);
      await controller.retry();
      expect(gateway.requests.last.key, original.key);
      expect(gateway.requests.last.draft.payload, original.draft.payload);
      expect(gateway.committed.length, 1);
      expect(controller.saved!.outcome, 'success');
    });
    test(
      'a definite transactional rejection is saved without posting',
      () async {
        prepare();
        gateway.failure = const ApiFailure(
          'INSUFFICIENT_FUNDS',
          'Insufficient',
          status: 400,
        );
        await controller.confirm();
        expect(controller.saved!.outcome, 'rejected');
        expect(gateway.committed, isEmpty);
        await controller.dismiss();
        expect(controller.saved, null);
      },
    );
    test('idempotency conflict never enables a new intent', () async {
      prepare();
      gateway.failure = const ApiFailure(
        'IDEMPOTENCY_CONFLICT',
        'Conflict',
        status: 409,
      );
      await controller.confirm();
      expect(controller.saved!.unresolved, true);
      await controller.dismiss();
      expect(await store.read(1), isNotNull);
      expect(controller.prepare(funded(1), funded(2).number, '1', ''), false);
    });
    test('journal write failure sends no request', () async {
      prepare();
      store.failClaim = true;
      await controller.confirm();
      expect(gateway.requests, isEmpty);
      expect(controller.ready, false);
      expect(controller.storageError, isNotNull);
    });
    test('resolution write failure keeps original pending record and recovers with one posting', () async {
      prepare();
      store.failResolve = true;
      await controller.confirm();
      expect((await store.read(1))!.unresolved, true);
      expect(controller.ready, false);
      store.failResolve = false;
      await controller.initialize();
      await controller.retry();
      expect(gateway.committed.length, 1);
      expect(controller.saved!.outcome, 'success');
    });
    test('logout during POST hides data, ignores receipt, and retains recovery record', () async {
      prepare();
      gateway.gate = Completer();
      final sending = controller.confirm();
      await Future<void>.delayed(Duration.zero);
      await session.signOut();
      expect(controller.saved, null);
      expect(controller.review, null);
      expect(controller.receipt, null);
      gateway.gate!.complete();
      await sending;
      expect((await store.read(1))!.unresolved, true);
      expect(controller.receipt, null);
    });
    test('401 invalidates session, preserves intent and never automatically replays', () async {
      prepare();
      gateway.failure = const ApiFailure(
        'TOKEN_INVALID',
        'Expired',
        status: 401,
      );
      await controller.confirm();
      expect(session.phase, SessionPhase.signedOut);
      expect(gateway.requests.length, 1);
      expect(auth.refreshCalls, 0);
      expect((await store.read(1))!.unresolved, true);
    });
    test(
      'restored confirmed result does a safe detail read and never posts',
      () async {
        prepare();
        await controller.confirm();
        controller.dispose();
        controller = TransferController(session, gateway, store);
        await controller.initialize();
        expect(controller.receipt!.status, 'SUCCESS');
        expect(gateway.requests.length, 1);
      },
    );
  });
  test(
    'history paginates, suppresses stale selection and clears on logout',
    () async {
      final auth = FakeGateway()..expiresInMs = 600000;
      final session = SessionController(auth, MemorySessionVault());
      await session.initialize();
      await session.begin(
        email: 'qa@example.test',
        password: 'Password1!',
        register: false,
      );
      await session.verifyCode('123456');
      final accountGateway = FakeAccounts()..data = [funded(1), funded(2)];
      final accounts = AccountsController(
        session,
        accountGateway,
        MemoryCreationStore(),
      );
      await accounts.initialize();
      final gateway = FakeTransactions();
      final record = SavedTransfer.confirmed(
        TransferDraft.validate(funded(1), funded(2).number, '1', ''),
      );
      gateway.historyItems = List.generate(
        25,
        (i) => posting(
          SavedTransfer(
            key: 'key-$i',
            draft: record.draft,
            createdAt: DateTime.utc(2026),
          ),
        ),
      );
      final history = HistoryController(session, accounts, gateway);
      try {
        await history.refresh();
        expect(history.items.length, 20);
        await history.loadMore();
        expect(history.items.length, 25);
        final late = Completer<PostingPage>();
        gateway.onHistory = (account, page) => account == funded(1).number
            ? late.future
            : Future.value(const PostingPage([], 0, true, 0));
        final refresh = history.refresh();
        await accounts.select(funded(2));
        late.complete(
          PostingPage(gateway.historyItems.take(20).toList(), 0, false, 25),
        );
        await refresh;
        expect(history.items, isEmpty);
        expect(history.accountNumber, funded(2).number);
        await session.signOut();
        expect(history.items, isEmpty);
        expect(history.accountNumber, null);
      } finally {
        history.dispose();
        accounts.dispose();
        session.dispose();
      }
    },
  );
}
