import 'dart:async';
import 'dart:convert';

import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/core/network/api_client.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/accounts/account_gateway.dart';
import 'package:customer_app/features/accounts/pair_opening.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:customer_app/features/qr/qr_controller.dart';
import 'package:customer_app/features/qr/qr_gateway.dart';
import 'package:customer_app/features/transactions/transfer_controller.dart';
import 'package:customer_app/features/transactions/transfer_models.dart';
import 'package:customer_app/features/transactions/transfer_store.dart';
import 'package:customer_app/features/transactions/transaction_gateway.dart';
import 'package:customer_app/shared/money.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';
import 'transactions_test.dart' show funded, FakeTransactions;

const sampleQr = '000201010211KesorFixture';
Map<String, dynamic> accountJson(String currency) => {
  'id': currency == 'USD' ? 1 : 2,
  'accountNumber': currency == 'USD' ? '1000000001' : '1000000002',
  'accountType': 'SAVINGS',
  'currency': currency,
  'balance': currency == 'USD' ? '200.00' : '100000',
  'status': 'ACTIVE',
  'createdAt': '2026-10-30T00:00:00Z',
};
AccountPairResult pairResult() => AccountPairResult.fromJson({
  'accounts': [accountJson('USD'), accountJson('KHR')],
  'testFundingApplied': true,
}, 'SAVINGS');
AccountQr qrResult({bool dynamic = false, String currency = 'USD'}) =>
    AccountQr.fromJson({
      'qrString': sampleQr,
      'qrHash': 'a' * 32,
      'accountNumber': '1000000001',
      'payeeName': 'Sok Dara',
      'currency': currency,
      'qrType': dynamic ? 'DYNAMIC' : 'STATIC',
      'amount': dynamic ? '10' : null,
    });
QrPreview previewResult({bool paid = false}) => QrPreview.fromJson({
  'valid': true,
  'qrString': sampleQr,
  'qrHash': 'a' * 32,
  'destinationAccountNumber': '1000000002',
  'destinationAccountName': 'Sok Dara',
  'currency': 'USD',
  'isDynamic': false,
  'isAlreadyPaid': paid,
  'amount': null,
  'remark': null,
});

class FakePairs implements AccountPairGateway {
  final requests = <(String, String)>[];
  bool timeout = false;
  Completer<AccountPairResult>? gate;
  @override
  Future<OpeningPolicy> openingPolicy(String token) async => OpeningPolicy(
    true,
    Money.parse('200', 'USD'),
    Money.parse('100000', 'KHR'),
  );
  @override
  Future<AccountPairResult> openPair(
    String token,
    String type,
    String key,
  ) async {
    requests.add((type, key));
    if (timeout) {
      timeout = false;
      throw const ApiFailure('TIMEOUT', 'Timed out');
    }
    return gate == null ? pairResult() : gate!.future;
  }
}

class FakeQr implements QrGateway {
  int scans = 0, polls = 0;
  bool paidValue = false;
  Completer<QrPreview>? gate;
  @override
  Future<AccountQr> generate(
    String token,
    BankAccount account,
    Money? amount,
  ) async => qrResult(dynamic: amount != null);
  @override
  Future<QrPreview> preview(String token, String payload) async {
    scans++;
    return gate == null ? previewResult() : gate!.future;
  }

  @override
  Future<bool> paid(String token, String hash) async {
    polls++;
    return paidValue;
  }
}

Future<SessionController> signedSession() async {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'paired opening survives recreation and retries the immutable request',
    () async {
      final session = await signedSession();
      final gateway = FakePairs()..timeout = true;
      final store = PairOpeningStore();
      var refreshes = 0;
      var model = PairOpeningController(
        session,
        gateway,
        store,
        onSuccess: () async {
          refreshes++;
        },
      );
      await model.initialize();
      expect(await model.open('SAVINGS'), false);
      final key = model.pending!.key;
      expect(await model.open('SAVINGS'), false);
      model.dispose();
      model = PairOpeningController(
        session,
        gateway,
        store,
        onSuccess: () async {
          refreshes++;
        },
      );
      await model.initialize();
      expect(model.pending!.key, key);
      expect(await model.retry(), true);
      expect(gateway.requests, [('SAVINGS', key), ('SAVINGS', key)]);
      expect(await store.read(1), null);
      expect(refreshes, 1);
      model.dispose();
      session.dispose();
    },
  );
  test(
    'pair secure records are namespaced and conflict with another opening',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final original = PairOpeningStore(namespace: 'api-a');
      const request = PairOpeningRequest('pair-key', 'SAVINGS');
      await original.claim(1, request);
      expect(
        (await PairOpeningStore(namespace: 'api-a').read(1))!.key,
        request.key,
      );
      expect(await PairOpeningStore(namespace: 'api-b').read(1), null);
      expect(await original.read(2), null);
      await expectLater(original.claim(1, request), throwsA(isA<ApiFailure>()));
      await original.clear(1, request);
      expect(await original.read(1), null);
    },
  );
  test(
    'late pair response after logout cannot update another session',
    () async {
      final session = await signedSession(),
          gateway = FakePairs()..gate = Completer<AccountPairResult>();
      final store = PairOpeningStore();
      var refreshes = 0;
      final model = PairOpeningController(
        session,
        gateway,
        store,
        onSuccess: () async {
          refreshes++;
        },
      );
      await model.initialize();
      final pending = model.open('SAVINGS');
      await Future<void>.delayed(Duration.zero);
      await session.signOut();
      gateway.gate!.complete(pairResult());
      await pending;
      expect(model.result, null);
      expect(refreshes, 0);
      expect(await store.read(1), isNotNull);
      model.dispose();
      session.dispose();
    },
  );
  test(
    'scan duplicates are suppressed and late responses are discarded',
    () async {
      final session = await signedSession(),
          gateway = FakeQr()..gate = Completer<QrPreview>();
      final model = QrController(session, gateway);
      final first = model.scan(sampleQr);
      expect(await model.scan(sampleQr), false);
      expect(gateway.scans, 1);
      await session.signOut();
      gateway.gate!.complete(previewResult());
      expect(await first, false);
      expect(model.preview, null);
      model.dispose();
      session.dispose();
    },
  );
  testWidgets('fixed request polling stops when hidden, paid or disposed', (
    tester,
  ) async {
    final session = await signedSession(), gateway = FakeQr();
    final model = QrController(
      session,
      gateway,
      pollInterval: const Duration(seconds: 1),
    );
    await model.generate(funded(1), Money.parse('10', 'USD'));
    await tester.pump(const Duration(seconds: 1));
    expect(gateway.polls, 1);
    model.setVisible(false);
    await tester.pump(const Duration(seconds: 3));
    expect(gateway.polls, 1);
    model.setVisible(true);
    gateway.paidValue = true;
    await tester.pump(const Duration(seconds: 1));
    expect(model.isPaid, true);
    await tester.pump(const Duration(seconds: 3));
    expect(gateway.polls, 2);
    model.dispose();
    session.dispose();
    await tester.pump(const Duration(seconds: 3));
  });
  testWidgets(
    'a replacement fixed QR keeps polling after an older status request finishes',
    (tester) async {
      final session = await signedSession(), gateway = SlowPollQr();
      var refreshed = 0;
      final model = QrController(
        session,
        gateway,
        pollInterval: const Duration(seconds: 1),
        onPaid: () async {
          refreshed++;
        },
      );
      await model.generate(funded(1), Money.parse('10', 'USD'));
      await tester.pump(const Duration(seconds: 1));
      expect(gateway.polls, 1);
      await model.generate(funded(1), Money.parse('11', 'USD'));
      await tester.pump(const Duration(seconds: 1));
      gateway.paidValue = true;
      gateway.firstPoll.complete(false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(gateway.polls, 2);
      expect(model.isPaid, true);
      expect(refreshed, 1);
      model.dispose();
      session.dispose();
    },
  );
  test(
    'saved QR payments keep v2 details and v1 manual records stay compatible',
    () async {
      final draft = TransferDraft(
        '1000000001',
        '1000000002',
        Money.parse('10', 'USD'),
        null,
        qrString: sampleQr,
        destinationName: 'Sok Dara',
      );
      final qr = SavedTransfer.confirmed(draft);
      final restored = SavedTransfer.fromJson(
        jsonDecode(jsonEncode(qr.toJson())),
      );
      expect(restored.draft.qrPayload, draft.qrPayload);
      expect(restored.draft.destinationName, 'Sok Dara');
      final manual = SavedTransfer.confirmed(
        TransferDraft(draft.source, draft.destination, draft.amount, null),
      );
      expect(manual.toJson()['version'], 1);
      expect(SavedTransfer.fromJson(manual.toJson()).draft.isQr, false);
      final malformed = qr.toJson()..remove('qrString');
      expect(
        () => SavedTransfer.fromJson(malformed),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
  test('unknown QR outcome blocks manual payments and retries exactly after restart', () async {
    final session = await signedSession(),
        gateway = FakeTransactions()..loseResponse = true;
    final store = MemoryTransferStore();
    var model = TransferController(session, gateway, store);
    await model.initialize();
    expect(
      model.prepare(
        funded(1),
        funded(2).number,
        '10',
        '',
        qrString: sampleQr,
        destinationName: 'Sok Dara',
      ),
      true,
    );
    await model.confirm();
    expect(model.saved!.unresolved, true);
    expect(model.prepare(funded(1), funded(3).number, '1', ''), false);
    final key = model.saved!.key;
    model.dispose();
    model = TransferController(session, gateway, store);
    await model.initialize();
    expect(gateway.requests.length, 1);
    await model.retry();
    expect(gateway.requests.map((r) => r.key), [key, key]);
    expect(gateway.committed.length, 1);
    expect(model.saved!.outcome, 'success');
    model.dispose();
    session.dispose();
  });
  test(
    'QR gateway uses nested standard receipt and original idempotency key',
    () async {
      final operation = SavedTransfer.confirmed(
        TransferDraft(
          '1000000001',
          '1000000002',
          Money.parse('10', 'USD'),
          null,
          qrString: sampleQr,
          destinationName: 'Sok Dara',
        ),
      );
      final client = ApiClient(
        AppConfig(
          apiBaseUrl: 'http://localhost:8080/api/v1',
          environment: 'dev',
        ),
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/payments/qr/transfer');
          expect(request.headers['Idempotency-Key'], operation.key);
          expect(jsonDecode(request.body)['qrString'], sampleQr);
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'transaction': {
                  'referenceNumber': 'TXN-qr',
                  'sourceAccountNumber': operation.draft.source,
                  'destinationAccountNumber': operation.draft.destination,
                  'amount': '10.00',
                  'fee': '0.00',
                  'currency': 'USD',
                  'transactionType': 'TRANSFER',
                  'status': 'SUCCESS',
                  'remark': null,
                  'createdAt': '2026-10-30T00:00:00Z',
                },
              },
            }),
            200,
          );
        }),
      );
      expect(
        (await HttpTransactionGateway(
          client,
        ).transfer('access', operation)).reference,
        'TXN-qr',
      );
    },
  );
  test('QR scan rejects already-paid requests and malformed amounts', () async {
    final session = await signedSession();
    final model = QrController(session, _PaidQr());
    expect(await model.scan(sampleQr), false);
    expect(model.error!.code, 'PAYMENT_ALREADY_COMPLETED');
    expect(
      () => AccountQr.fromJson({
        'qrString': sampleQr,
        'qrHash': 'a' * 32,
        'accountNumber': '1000000001',
        'payeeName': 'Sok',
        'currency': 'KHR',
        'qrType': 'DYNAMIC',
        'amount': '1.2',
      }),
      throwsA(isA<ApiFailure>()),
    );
    model.dispose();
    session.dispose();
  });
}

class _PaidQr extends FakeQr {
  @override
  Future<QrPreview> preview(String token, String payload) async =>
      previewResult(paid: true);
}

class SlowPollQr extends FakeQr {
  final firstPoll = Completer<bool>();
  @override
  Future<bool> paid(String token, String hash) async {
    polls++;
    return polls == 1 ? firstPoll.future : paidValue;
  }
}
