import 'package:flutter/foundation.dart';
import 'package:kesor_auth_handoff/kesor_auth_handoff.dart';

import '../collect/merchant_collect.dart';
import '../shop/merchant_shop.dart';

enum TransferStatus { pending, completed, denied, cancelled, expired, failed }

/// One owner transfer: a business wallet to the owner's own wallet, approved in Kesor Bank.
///
/// The server chooses the destination and shows it masked. [approvalUri] and [state] are present
/// only on create (or a replayed create) while the transfer is waiting.
@immutable
class OwnerTransfer {
  const OwnerTransfer({
    required this.id,
    required this.status,
    required this.sourceAccountNumber,
    required this.destinationAccount,
    required this.currency,
    required this.amount,
    required this.createdAt,
    required this.expiresAt,
    required this.serverTime,
    this.failureCode,
    this.receiptReference,
    this.completedAt,
    this.approvalUri,
    this.state,
  });
  final String id, sourceAccountNumber, destinationAccount, currency, amount;
  final TransferStatus status;
  final DateTime createdAt, expiresAt, serverTime;
  final String? failureCode, receiptReference, approvalUri, state;
  final DateTime? completedAt;

  bool get waiting => status == TransferStatus.pending;

  /// Time left by the server's clock, independent of the device clock.
  Duration get remainingAtFetch => expiresAt.difference(serverTime);

  static final _masked = RegExp(r'^•••• [0-9]{4}$');
  static final _id = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  static OwnerTransfer fromJson(Map json) => parseShopResponse(() {
    final id = responseText(json['intentId']);
    if (!_id.hasMatch(id)) throw const ShopFailure('INVALID_RESPONSE');
    final currency = responseCurrency(json['currency']);
    final destination = responseText(json['destinationAccount']);
    final source = responseText(json['sourceAccountNumber']);
    if (!_masked.hasMatch(destination) ||
        !RegExp(r'^[0-9]{10,20}$').hasMatch(source)) {
      throw const ShopFailure('INVALID_RESPONSE');
    }
    final status = switch (json['status']) {
      'PENDING' => TransferStatus.pending,
      'COMPLETED' => TransferStatus.completed,
      'DENIED' => TransferStatus.denied,
      'CANCELLED' => TransferStatus.cancelled,
      'EXPIRED' => TransferStatus.expired,
      'FAILED' => TransferStatus.failed,
      _ => throw const ShopFailure('INVALID_RESPONSE'),
    };
    final receipt = json['receipt'];
    if (status == TransferStatus.completed && receipt is! Map) {
      throw const ShopFailure('INVALID_RESPONSE');
    }
    final uri = json['approvalUri'] as String?;
    final state = json['state'] as String?;
    if (uri != null) {
      // Only the exact registered link, for this very transfer, is ever opened.
      final fields = exactLink(uri, transferApprovalBase, {
        'intentId',
        'handoffToken',
      });
      if (fields['intentId'] != id || !credential(fields['handoffToken'])) {
        throw const ShopFailure('INVALID_RESPONSE');
      }
    }
    if ((uri != null) != (state != null) ||
        (state != null && !credential(state))) {
      throw const ShopFailure('INVALID_RESPONSE');
    }
    return OwnerTransfer(
      id: id,
      status: status,
      sourceAccountNumber: source,
      destinationAccount: destination,
      currency: currency,
      amount: responseMoney(json['amount'], currency),
      createdAt: responseTime(json['createdAt']),
      expiresAt: responseTime(json['expiresAt']),
      serverTime: responseTime(json['serverTime']),
      failureCode: json['failureCode'] as String?,
      receiptReference: receipt is Map
          ? responseText(receipt['reference'])
          : null,
      completedAt: receipt is Map ? responseTime(receipt['completedAt']) : null,
      approvalUri: uri,
      state: state,
    );
  });
}

/// Merchant-session owner-transfer APIs (M8). The Merchant app never sees a PIN or a Customer token.
abstract interface class OwnerTransferGateway {
  /// Creates the transfer, or replays it for the same [idempotencyKey] and body.
  Future<OwnerTransfer> createOwnerTransfer(
    String idempotencyKey, {
    required String sourceAccountNumber,
    required String amount,
  });
  Future<OwnerTransfer> ownerTransferStatus(String id);
  Future<OwnerTransfer> cancelOwnerTransfer(String id);
}
