import 'package:flutter/foundation.dart';

import '../shop/merchant_shop.dart';

/// A confirmed QR payment. Amount/currency are what the shop received.
@immutable
class ShopReceipt {
  const ShopReceipt({
    required this.reference,
    required this.currency,
    required this.amount,
    required this.paidCurrency,
    required this.paidAmount,
    required this.payerName,
    required this.payerAccount,
    required this.paidAt,
    this.requestReference,
    this.orderReference,
  });
  final String reference, currency, amount, paidCurrency, paidAmount;
  final String payerName, payerAccount;
  final String? requestReference, orderReference;
  final DateTime paidAt;
  bool get converted => paidCurrency != currency;

  static ShopReceipt fromJson(Map json) => ShopReceipt(
    reference: json['reference'] as String,
    currency: json['currency'] as String,
    amount: json['amount'] as String,
    paidCurrency: json['paidCurrency'] as String,
    paidAmount: json['paidAmount'] as String,
    payerName: json['payerName'] as String,
    payerAccount: json['payerAccount'] as String,
    requestReference: json['requestReference'] as String?,
    orderReference: json['orderReference'] as String?,
    paidAt: DateTime.parse(json['paidAt'] as String),
  );
}

@immutable
class CurrencyTotal {
  const CurrencyTotal(this.currency, this.count, this.gross);
  final String currency, gross;
  final int count;
}

@immutable
class ShopDashboard {
  const ShopDashboard({
    required this.profile,
    required this.businessDate,
    this.today = const [],
    this.recent = const [],
  });
  final ShopProfile profile;
  final String businessDate;
  final List<CurrencyTotal> today;
  final List<ShopReceipt> recent;
}

@immutable
class WalletActivity {
  const WalletActivity({
    required this.reference,
    required this.kind,
    required this.incoming,
    required this.amount,
    required this.currency,
    required this.createdAt,
    this.payerName,
    this.payerAccount,
  });

  /// QR_PAYMENT, TRANSFER_IN, TRANSFER_OUT or DEPOSIT.
  final String reference, kind, amount, currency;
  final bool incoming;
  final String? payerName, payerAccount;
  final DateTime createdAt;
}

@immutable
class WalletPage {
  const WalletPage(this.wallet, this.activity, this.page, this.hasMore);
  final ShopWallet wallet;
  final List<WalletActivity> activity;
  final int page;
  final bool hasMore;
}

@immutable
class ShopQr {
  const ShopQr({
    required this.qrString,
    required this.currency,
    required this.accountNumber,
    required this.storeName,
  });
  final String qrString, currency, accountNumber, storeName;
}

enum RequestStatus { waiting, paid, expired, cancelled }

@immutable
class PaymentRequest {
  const PaymentRequest({
    required this.id,
    required this.reference,
    required this.status,
    required this.currency,
    required this.amount,
    required this.expiresAt,
    required this.serverTime,
    this.orderReference,
    this.qrString,
    this.receipt,
  });
  final String id, reference, currency, amount;
  final RequestStatus status;
  final String? orderReference, qrString;
  final DateTime expiresAt, serverTime;
  final ShopReceipt? receipt;

  /// Time left by the server's clock, independent of the device clock.
  Duration get remainingAtFetch => expiresAt.difference(serverTime);

  static PaymentRequest fromJson(Map json) => PaymentRequest(
    id: json['requestId'] as String,
    reference: json['reference'] as String,
    status: switch (json['status']) {
      'WAITING' => RequestStatus.waiting,
      'PAID' => RequestStatus.paid,
      'EXPIRED' => RequestStatus.expired,
      'CANCELLED' => RequestStatus.cancelled,
      _ => throw const ShopFailure('INVALID_RESPONSE'),
    },
    currency: json['currency'] as String,
    amount: json['amount'] as String,
    orderReference: json['orderReference'] as String?,
    qrString: json['qrString'] as String?,
    expiresAt: DateTime.parse(json['expiresAt'] as String),
    serverTime: DateTime.parse(json['serverTime'] as String),
    receipt: json['receipt'] is Map
        ? ShopReceipt.fromJson(json['receipt'] as Map)
        : null,
  );
}

/// Merchant-session dashboard, wallet and collection APIs (M5/M6).
abstract interface class MerchantCollectGateway {
  Future<ShopDashboard> dashboard();
  Future<WalletPage> wallet(String accountNumber, {int page = 0});
  Future<ShopQr> shopQr(String currency);
  Future<PaymentRequest> createRequest(
    String idempotencyKey, {
    required String currency,
    required String amount,
    String? orderReference,
  });
  Future<PaymentRequest> requestStatus(String id);
  Future<PaymentRequest> cancelRequest(String id);
}
