import 'package:flutter/foundation.dart';

import '../shop/merchant_shop.dart';
import '../transfer/owner_transfer.dart';

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
    this.storeName,
    this.walletAccountNumber,
    this.exchangeRate,
  });
  final String reference, currency, amount, paidCurrency, paidAmount;
  final String payerName, payerAccount;
  final String? requestReference, orderReference;
  final String? storeName, walletAccountNumber, exchangeRate;
  final DateTime paidAt;
  bool get converted => paidCurrency != currency;

  static ShopReceipt fromJson(Map json) => parseShopResponse(() {
    final currency = responseCurrency(json['currency']);
    final paidCurrency = responseCurrency(json['paidCurrency']);
    final masked = responseText(json['payerAccount']);
    final wallet = responseText(json['walletAccountNumber']);
    if (!RegExp(r'^•••• [0-9]{4}$').hasMatch(masked)) {
      throw const ShopFailure('INVALID_RESPONSE');
    }
    if (!RegExp(r'^[0-9]{10,20}$').hasMatch(wallet)) {
      throw const ShopFailure('INVALID_RESPONSE');
    }
    if (json['exchangeRate'] != null &&
        (json['exchangeRate'] is! String ||
            !RegExp(r'^[0-9]+(\.[0-9]+)?$')
                .hasMatch(json['exchangeRate'] as String))) {
      throw const ShopFailure('INVALID_RESPONSE');
    }
    return ShopReceipt(
      reference: responseText(json['reference']),
      currency: currency,
      amount: responseMoney(json['amount'], currency),
      paidCurrency: paidCurrency,
      paidAmount: responseMoney(json['paidAmount'], paidCurrency),
      payerName: responseText(json['payerName']),
      payerAccount: masked,
      requestReference: json['requestReference'] as String?,
      orderReference: json['orderReference'] as String?,
      paidAt: responseTime(json['paidAt']),
      storeName: responseText(json['storeName']),
      walletAccountNumber: wallet,
      exchangeRate: json['exchangeRate'] as String?,
    );
  });
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
abstract interface class MerchantCollectGateway
    implements OwnerTransferGateway {
  Future<SalesPage> sales(SalesFilter filter, {String? cursor});
  Future<ShopReceipt> receipt(String reference);
  Future<CollectionReport> report({
    required String period,
    required String from,
    required String to,
  });
  Future<RequestHistory> requestHistory({
    RequestStatus? status,
    String? cursor,
  });
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

T parseShopResponse<T>(T Function() parse) {
  try {
    return parse();
  } on ShopFailure {
    rethrow;
  } catch (_) {
    throw const ShopFailure('INVALID_RESPONSE');
  }
}

String responseText(dynamic value) {
  if (value is! String || value.isEmpty) {
    throw const ShopFailure('INVALID_RESPONSE');
  }
  return value;
}

String responseCurrency(dynamic value) {
  if (value != 'KHR' && value != 'USD') {
    throw const ShopFailure('INVALID_RESPONSE');
  }
  return value as String;
}

String responseMoney(dynamic value, String currency) {
  if (value is! String ||
      !(currency == 'KHR' ? RegExp(r'^[0-9]+$') : RegExp(r'^[0-9]+\.[0-9]{2}$'))
          .hasMatch(value)) {
    throw const ShopFailure('INVALID_RESPONSE');
  }
  return value;
}

DateTime responseTime(dynamic value) {
  final text = responseText(value);
  if (!RegExp(r'(Z|[+-][0-9]{2}:[0-9]{2})$').hasMatch(text)) {
    throw const ShopFailure('INVALID_RESPONSE');
  }
  return DateTime.parse(text);
}

/// All dates and group keys use the fixed UTC+7 business zone, not the device zone.
DateTime businessTime(DateTime value) =>
    value.toUtc().add(const Duration(hours: 7));
DateTime businessToday() {
  final d = businessTime(DateTime.now());
  return DateTime.utc(d.year, d.month, d.day);
}

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
BigInt moneyUnits(String amount, String currency) =>
    BigInt.parse(currency == 'KHR' ? amount : amount.replaceAll('.', ''));
String unitsMoney(BigInt amount, String currency) => currency == 'KHR'
    ? '$amount'
    : '${amount ~/ BigInt.from(100)}.${(amount % BigInt.from(100)).toString().padLeft(2, '0')}';

@immutable
class SalesFilter {
  const SalesFilter({
    required this.from,
    required this.to,
    this.currency,
    this.q = '',
  });
  factory SalesFilter.today() =>
      SalesFilter(from: dateKey(businessToday()), to: dateKey(businessToday()));
  final String from, to, q;
  final String? currency;
  Map<String, String> get query => {
    'from': from,
    'to': to,
    'currency': ?currency,
    if (q.isNotEmpty) 'q': q,
  };
}

List<CurrencyTotal> parseTotals(dynamic list) => [
  for (final t in list as List)
    CurrencyTotal(
      responseCurrency(t['currency']),
      t['count'] as int,
      responseMoney(t['gross'], responseCurrency(t['currency'])),
    ),
];

@immutable
class SalesPage {
  const SalesPage(this.items, this.nextCursor, this.totals);
  final List<ShopReceipt> items;
  final String? nextCursor;
  final List<CurrencyTotal> totals;
  static SalesPage fromJson(Map json) => parseShopResponse(
    () => SalesPage(
      [for (final r in json['items'] as List) ShopReceipt.fromJson(r as Map)],
      json['nextCursor'] as String?,
      parseTotals(json['totals']),
    ),
  );
}

@immutable
class ReportBucket {
  const ReportBucket(this.bucket, this.currency, this.count, this.gross);
  final String bucket, currency, gross;
  final int count;
}

@immutable
class CollectionReport {
  const CollectionReport(this.period, this.buckets, this.totals);
  final String period;
  final List<ReportBucket> buckets;
  final List<CurrencyTotal> totals;
  static CollectionReport fromJson(Map json) => parseShopResponse(() {
    if (!{'DAY', 'MONTH'}.contains(json['period'])) {
      throw const ShopFailure('INVALID_RESPONSE');
    }
    return CollectionReport(json['period'] as String, [
      for (final b in json['buckets'] as List)
        ReportBucket(
          responseText(b['bucket']),
          responseCurrency(b['currency']),
          b['count'] as int,
          responseMoney(b['gross'], responseCurrency(b['currency'])),
        ),
    ], parseTotals(json['totals']));
  });
}

@immutable
class RequestSummary {
  const RequestSummary(
    this.id,
    this.reference,
    this.status,
    this.currency,
    this.amount,
    this.createdAt,
    this.expiresAt, {
    this.orderReference,
  });
  final String id, reference, currency, amount;
  final RequestStatus status;
  final DateTime createdAt, expiresAt;
  final String? orderReference;
  static RequestSummary fromJson(Map json) => parseShopResponse(
    () => RequestSummary(
      responseText(json['requestId']),
      responseText(json['reference']),
      switch (json['status']) {
        'WAITING' => RequestStatus.waiting,
        'PAID' => RequestStatus.paid,
        'EXPIRED' => RequestStatus.expired,
        'CANCELLED' => RequestStatus.cancelled,
        _ => throw const ShopFailure('INVALID_RESPONSE'),
      },
      responseCurrency(json['currency']),
      responseMoney(json['amount'], responseCurrency(json['currency'])),
      responseTime(json['createdAt']),
      responseTime(json['expiresAt']),
      orderReference: json['orderReference'] as String?,
    ),
  );
}

@immutable
class RequestHistory {
  const RequestHistory(this.items, this.nextCursor);
  final List<RequestSummary> items;
  final String? nextCursor;
  static RequestHistory fromJson(Map json) => parseShopResponse(
    () => RequestHistory([
      for (final r in json['items'] as List) RequestSummary.fromJson(r as Map),
    ], json['nextCursor'] as String?),
  );
}
