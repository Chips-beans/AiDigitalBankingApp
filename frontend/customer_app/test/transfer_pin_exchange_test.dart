import 'dart:typed_data';

import 'package:customer_app/core/network/api_client.dart';
import 'package:customer_app/core/storage/session_vault.dart';
import 'package:customer_app/features/accounts/account_gateway.dart';
import 'package:customer_app/features/auth/session_controller.dart';
import 'package:customer_app/features/transactions/transfer_controller.dart';
import 'package:customer_app/features/transactions/transfer_models.dart';
import 'package:customer_app/features/transactions/transfer_store.dart';
import 'package:customer_app/features/transactions/transfer_support.dart';
import 'package:customer_app/shared/money.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'transactions_test.dart' show FakeTransactions, funded;

class ProofRecordingTransactions extends FakeTransactions {
  final proofs = <String?>[];
  @override
  Future<RecentPosting> transfer(
    String token,
    SavedTransfer operation, {
    String? pinProof,
  }) {
    proofs.add(pinProof);
    return super.transfer(token, operation, pinProof: pinProof);
  }
}

class FakeSupport implements TransferSupportGateway {
  final pins = <String>[];
  int issued = 0;
  TransferQuote? nextQuote;
  @override
  Future<String> transferProof(String token, String pin) async {
    pins.add(pin);
    if (pin != '0427') {
      throw const ApiFailure('PIN_INVALID', 'The PIN did not match', status: 403);
    }
    return 'proof-${++issued}';
  }

  @override
  Future<TransferQuote> quote(
    String token,
    String source,
    String destination,
    Money amount,
  ) async => nextQuote ?? TransferQuote(amount, amount, '1.0000', false);
  @override
  Future<Recipient> lookup(String token, String accountNumber) async =>
      Recipient(accountNumber, 'USD', 'Sok Dara', false);
  @override
  Future<Uint8List?> photo(String token, String accountNumber) async => null;
}

void main() {
  group('fixed-rate conversion helper', () {
    test('mirrors the server: exact or refused, never rounded', () {
      expect(exactDebitFor(Money.parse('10000', 'KHR'), 'USD')!.decimal, '2.50');
      expect(exactDebitFor(Money.parse('40', 'KHR'), 'USD')!.decimal, '0.01');
      expect(exactDebitFor(Money.parse('10001', 'KHR'), 'USD'), isNull);
      expect(exactDebitFor(Money.parse('2.50', 'USD'), 'KHR')!.decimal, '10000');
      expect(exactDebitFor(Money.parse('7.25', 'USD'), 'USD')!.decimal, '7.25');
    });
  });

  test('fixed QR payments omit the amount so the server debits the exact equivalent', () {
    final draft = TransferDraft(
      '1000000001',
      '1000000002',
      Money.parse('2.50', 'USD'),
      null,
      qrString: 'qr',
      destinationName: 'Shop',
      qrFixed: true,
    );
    expect(draft.qrPayload.containsKey('amount'), false);
    expect(draft.qrPayload['currency'], 'USD');
    final record = SavedTransfer.fromJson(SavedTransfer.confirmed(draft).toJson());
    expect(record.draft.qrFixed, true);
  });

  test('a converted transfer shows each account its own side', () {
    final json = {
      'referenceNumber': 'TXN-1',
      'sourceAccountNumber': '1000000001',
      'destinationAccountNumber': '1000000002',
      'amount': '10001',
      'fee': '0',
      'currency': 'KHR',
      'creditAmount': '2.50',
      'creditCurrency': 'USD',
      'exchangeRate': '4000.0000',
      'transactionType': 'TRANSFER',
      'status': 'SUCCESS',
      'createdAt': '2026-10-31T00:00:00Z',
      'sourceName': 'Sok Dara',
      'destinationName': 'Chan Lina',
    };
    final sender = RecentPosting.fromJson(json, '1000000001');
    final receiver = RecentPosting.fromJson(json, '1000000002');
    expect(sender.amount.formatted, 'KHR 10,001');
    expect(receiver.amount.formatted, 'USD 2.50');
    expect(receiver.debit.formatted, 'KHR 10,001');
    expect(receiver.sourceName, 'Sok Dara');
    expect(receiver.converted, true);
    final bank = RecentPosting.fromJson({
      ...json,
      'sourceAccountNumber': null,
      'transactionType': 'DEPOSIT',
      'currency': 'USD',
      'amount': '200.00',
      'creditAmount': '200.00',
      'creditCurrency': 'USD',
      'exchangeRate': null,
      'sourceName': 'Kesor Bank',
      'bankSource': true,
    }, '1000000002');
    expect(bank.bankSource, true);
    expect(bank.sourceName, 'Kesor Bank');
    expect(bank.converted, false);
  });

  group('PIN at transfer confirmation', () {
    late SessionController session;
    late ProofRecordingTransactions gateway;
    late MemoryTransferStore store;
    late FakeSupport support;
    late TransferController controller;
    setUp(() async {
      session = SessionController(
        FakeGateway()..expiresInMs = 600000,
        MemorySessionVault(),
      );
      await session.initialize();
      await session.begin(
        email: 'qa@example.test',
        password: 'Password1!',
        register: false,
      );
      await session.verifyCode('123456');
      gateway = ProofRecordingTransactions();
      store = MemoryTransferStore();
      support = FakeSupport();
      controller = TransferController(session, gateway, store, support: support);
      await controller.initialize();
    });
    tearDown(() {
      controller.dispose();
      session.dispose();
    });

    test('no PIN or a wrong PIN sends and saves nothing', () async {
      expect(controller.prepare(funded(1), funded(2).number, '5', ''), true);
      await controller.confirm();
      expect(controller.error!.code, 'PIN_REQUIRED');
      await controller.confirm(pin: '9999');
      expect(controller.error!.code, 'PIN_INVALID');
      expect(gateway.requests, isEmpty);
      expect(await store.read(1), isNull);
      expect(controller.review, isNotNull, reason: 'the reviewed draft stays for another try');
    });

    test('the correct PIN yields one proof that travels with the transfer only', () async {
      expect(controller.prepare(funded(1), funded(2).number, '5', ''), true);
      await controller.confirm(pin: '0427');
      expect(controller.saved!.outcome, 'success');
      expect(gateway.proofs, ['proof-1']);
      final persisted = (await store.read(1))!.toJson().toString();
      expect(persisted, isNot(contains('proof')));
      expect(persisted, isNot(contains('0427')));
    });

    // Regression (device, 31 Oct): the name was kept in memory but not persisted, so
    // resolving the confirmed transfer failed the stored-record check.
    test('a manual transfer with a verified receiver name resolves to success', () async {
      expect(
        controller.prepare(
          funded(1),
          funded(2).number,
          '12',
          '',
          destinationName: 'Seng Sovanreach',
        ),
        true,
      );
      await controller.confirm(pin: '0427');
      expect(controller.storageError, isNull);
      expect(controller.saved!.outcome, 'success');
      final stored = (await store.read(1))!;
      expect(stored.draft.destinationName, 'Seng Sovanreach');
      expect(stored.draft.isQr, false);
    });

    test('the review shows the server quote for a converted transfer', () async {
      support.nextQuote = TransferQuote(
        Money.parse('10001', 'KHR'),
        Money.parse('2.50', 'USD'),
        '4000.0000',
        true,
      );
      expect(
        controller.prepare(
          funded(1, currency: 'KHR', balance: '20000'),
          funded(2).number,
          '10001',
          '',
        ),
        true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.quote!.converted, true);
      expect(controller.quote!.credit.formatted, 'USD 2.50');
    });
  });
}
