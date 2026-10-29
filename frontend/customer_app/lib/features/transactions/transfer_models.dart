import 'dart:math';

import '../../core/network/api_client.dart';
import '../../shared/money.dart';
import '../accounts/account_gateway.dart';

const invalidTransfer = ApiFailure(
  'INVALID_TRANSFER',
  'The saved transfer could not be verified. Sending is blocked to protect against duplicate transfers.',
);

class TransferDraft {
  const TransferDraft(this.source, this.destination, this.amount, this.remark);
  factory TransferDraft.validate(
    BankAccount source,
    String destination,
    String input,
    String remark,
  ) {
    destination = destination.trim();
    if (source.status != 'ACTIVE') {
      throw const ApiFailure(
        'ACCOUNT_INACTIVE',
        'Choose an active source account.',
      );
    }
    if (!RegExp(r'^[0-9]{10,20}$').hasMatch(destination) ||
        source.number == destination) {
      throw const ApiFailure(
        'INVALID_DESTINATION',
        'Enter a different destination account number with 10–20 digits.',
      );
    }
    input = input.trim();
    final valid = source.currency == 'USD'
        ? RegExp(r'^[0-9]+(?:\.[0-9]{1,2})?$')
        : RegExp(r'^[0-9]+$');
    if (!valid.hasMatch(input)) {
      throw ApiFailure(
        'INVALID_AMOUNT',
        source.currency == 'USD'
            ? 'Enter an amount with at most two decimal places.'
            : 'Enter a whole KHR amount.',
      );
    }
    Money money;
    try {
      money = Money.parse(input, source.currency);
    } on ApiFailure {
      throw const ApiFailure(
        'INVALID_AMOUNT',
        'Enter an amount within the supported range.',
      );
    }
    if (money.minorUnits <= BigInt.zero) {
      throw const ApiFailure(
        'INVALID_AMOUNT',
        'Amount must be greater than zero.',
      );
    }
    if (money.minorUnits > source.balance.minorUnits) {
      throw const ApiFailure(
        'INSUFFICIENT_FUNDS',
        'The amount exceeds the last known available balance. Refresh your account.',
      );
    }
    if (remark.length > 255) {
      throw const ApiFailure(
        'INVALID_REMARK',
        'Remark must be 255 characters or fewer.',
      );
    }
    return TransferDraft(
      source.number,
      destination,
      money,
      remark.trim().isEmpty ? null : remark.trim(),
    );
  }
  final String source, destination;
  final Money amount;
  final String? remark;
  Map<String, dynamic> get payload => {
    'sourceAccountNumber': source,
    'destinationAccountNumber': destination,
    'amount': amount.decimal,
    'currency': amount.currency,
    'remark': remark,
  };
}

class SavedTransfer {
  const SavedTransfer({
    required this.key,
    required this.draft,
    required this.createdAt,
    this.outcome = 'unresolved',
    this.reference,
    this.rejectionCode,
  });
  factory SavedTransfer.confirmed(TransferDraft draft) {
    final rng = Random.secure();
    return SavedTransfer(
      key:
          'transfer-${List.generate(24, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}',
      draft: draft,
      createdAt: DateTime.now().toUtc(),
    );
  }
  factory SavedTransfer.fromJson(Object? value) {
    try {
      final data = objectData(value);
      if (data['version'] != 1) throw invalidTransfer;
      final key = textField(data, 'key');
      final source = textField(data, 'source');
      final destination = textField(data, 'destination');
      final money = Money.parse(data['amount'], textField(data, 'currency'));
      final remark = data['remark'];
      final outcome = textField(data, 'outcome');
      final reference = data['reference'];
      final rejection = data['rejectionCode'];
      if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(key) ||
          !RegExp(r'^[0-9]{10,20}$').hasMatch(source) ||
          !RegExp(r'^[0-9]{10,20}$').hasMatch(destination) ||
          source == destination ||
          money.minorUnits <= BigInt.zero ||
          (remark != null && (remark is! String || remark.length > 255)) ||
          !{'unresolved', 'success', 'rejected'}.contains(outcome) ||
          (outcome == 'success' &&
              (reference is! String || reference.isEmpty)) ||
          (outcome != 'success' && reference != null) ||
          (outcome == 'rejected' &&
              (rejection is! String ||
                  !definiteRejections.contains(rejection))) ||
          (outcome != 'rejected' && rejection != null)) {
        throw invalidTransfer;
      }
      return SavedTransfer(
        key: key,
        draft: TransferDraft(source, destination, money, remark as String?),
        createdAt: dateField(data, 'createdAt'),
        outcome: outcome,
        reference: reference as String?,
        rejectionCode: rejection as String?,
      );
    } catch (_) {
      throw invalidTransfer;
    }
  }
  static const definiteRejections = {
    'INSUFFICIENT_FUNDS',
    'ACCOUNT_INACTIVE',
    'CURRENCY_MISMATCH',
    'INVALID_AMOUNT',
    'INVALID_REQUEST',
    'VALIDATION_FAILED',
    'RESOURCE_NOT_FOUND',
  };
  final String key, outcome;
  final TransferDraft draft;
  final DateTime createdAt;
  final String? reference, rejectionCode;
  bool get unresolved => outcome == 'unresolved';
  SavedTransfer resolve({String? reference, String? rejectionCode}) =>
      SavedTransfer(
        key: key,
        draft: draft,
        createdAt: createdAt,
        outcome: reference != null ? 'success' : 'rejected',
        reference: reference,
        rejectionCode: rejectionCode,
      );
  Map<String, dynamic> toJson() => {
    'version': 1,
    'key': key,
    'source': draft.source,
    'destination': draft.destination,
    'amount': draft.amount.decimal,
    'currency': draft.amount.currency,
    'remark': draft.remark,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'outcome': outcome,
    'reference': reference,
    'rejectionCode': rejectionCode,
  };
}
