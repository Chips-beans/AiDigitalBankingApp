import '../../core/network/api_client.dart';
import '../../shared/money.dart';
import '../accounts/account_gateway.dart';
import '../transactions/transfer_models.dart' show ShopPayee;

class AccountQr {
  AccountQr.fromJson(Object? value) {
    final data = objectData(value);
    payload = textField(data, 'qrString');
    hash = textField(data, 'qrHash');
    account = textField(data, 'accountNumber');
    name = textField(data, 'payeeName');
    currency = textField(data, 'currency');
    dynamic = data['qrType'] == 'DYNAMIC';
    if (data['qrType'] != 'STATIC' && !dynamic ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(hash) ||
        !payload.startsWith('000201') ||
        payload.length > 4096 ||
        !RegExp(r'^[0-9]{10,20}$').hasMatch(account) ||
        !{'USD', 'KHR'}.contains(currency)) {
      throw invalidAccountData;
    }
    amount = data['amount'] == null
        ? null
        : Money.parse(data['amount'], currency);
    if (dynamic && (amount == null || amount!.minorUnits <= BigInt.zero) ||
        !dynamic && amount != null) {
      throw invalidAccountData;
    }
  }
  late final String payload, hash, account, name, currency;
  late final bool dynamic;
  late final Money? amount;
}

class QrPreview {
  QrPreview.fromJson(Object? value) {
    final data = objectData(value);
    payload = textField(data, 'qrString');
    hash = textField(data, 'qrHash');
    destination = textField(data, 'destinationAccountNumber');
    name = textField(data, 'destinationAccountName');
    currency = textField(data, 'currency');
    if (data['valid'] != true ||
        data['isDynamic'] is! bool ||
        data['isAlreadyPaid'] is! bool ||
        !RegExp(r'^[0-9]{10,20}$').hasMatch(destination) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(hash) ||
        !payload.startsWith('000201') ||
        payload.length > 4096 ||
        !{'USD', 'KHR'}.contains(currency)) {
      throw invalidAccountData;
    }
    dynamic = data['isDynamic'] as bool;
    paid = data['isAlreadyPaid'] as bool;
    amount = data['amount'] == null
        ? null
        : Money.parse(data['amount'], currency);
    if (dynamic && (amount == null || amount!.minorUnits <= BigInt.zero) ||
        !dynamic && amount != null) {
      throw invalidAccountData;
    }
    remark = data['remark'] as String?;
    final merchant = data['merchant'];
    if (merchant is Map) {
      final id = merchant['merchantId'], store = merchant['storeName'];
      if (merchant['verified'] != true ||
          id is! String ||
          !RegExp(r'^MCH-[A-Z0-9]{8}$').hasMatch(id) ||
          store is! String ||
          store.trim().isEmpty ||
          store.length > 150 ||
          store != name) {
        throw invalidAccountData;
      }
      shop = ShopPayee(
        merchantId: id,
        storeName: store,
        currency: currency,
        hasLogo: merchant['hasLogo'] == true,
      );
    } else {
      shop = null;
    }
    expiresAt = DateTime.tryParse('${data['expiresAt']}');
  }
  late final String payload, hash, destination, name, currency;
  late final bool dynamic, paid;
  late final Money? amount;
  late final String? remark;

  /// The verified shop for a Kesor Merchant QR; null for personal QR codes.
  late final ShopPayee? shop;

  /// When a shop's fixed-amount request stops accepting payment.
  late final DateTime? expiresAt;
}

abstract interface class QrGateway {
  Future<AccountQr> generate(String token, BankAccount account, Money? amount);
  Future<QrPreview> preview(String token, String payload);
  Future<bool> paid(String token, String hash);
}

class HttpQrGateway implements QrGateway {
  HttpQrGateway(this.client);
  final ApiClient client;
  @override
  Future<AccountQr> generate(
    String token,
    BankAccount account,
    Money? amount,
  ) async {
    final result = AccountQr.fromJson(
      (await client.request(
        'POST',
        '/payments/qr/generate',
        accessToken: token,
        body: {
          'accountNumber': account.number,
          'currency': account.currency,
          'qrType': amount == null ? 'STATIC' : 'DYNAMIC',
          if (amount != null) 'amount': amount.decimal,
        },
      ))['data'],
    );
    if (result.account != account.number ||
        result.currency != account.currency ||
        result.amount?.minorUnits != amount?.minorUnits) {
      throw invalidAccountData;
    }
    return result;
  }

  @override
  Future<QrPreview> preview(String token, String payload) async {
    if (payload.isEmpty || payload.length > 4096) {
      throw const ApiFailure(
        'UNSUPPORTED_QR',
        'Only registered Kesor QR codes are supported.',
      );
    }
    final result = QrPreview.fromJson(
      (await client.request(
        'POST',
        '/payments/qr/scan',
        accessToken: token,
        body: {'qrString': payload},
      ))['data'],
    );
    if (result.payload != payload.trim()) throw invalidAccountData;
    return result;
  }

  @override
  Future<bool> paid(String token, String hash) async {
    final data = await client.request(
      'GET',
      '/payments/verify/${Uri.encodeComponent(hash)}',
      accessToken: token,
    );
    if (data['md5Hash'] != hash ||
        data['isPaid'] is! bool ||
        !{'PENDING', 'SUCCESS'}.contains(data['status'])) {
      throw invalidAccountData;
    }
    return data['isPaid'] as bool;
  }
}
