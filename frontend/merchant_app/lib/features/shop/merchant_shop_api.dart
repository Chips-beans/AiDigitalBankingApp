import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/merchant_config.dart';
import '../auth/merchant_session.dart';
import '../collect/merchant_collect.dart';
import 'merchant_shop.dart';

/// Merchant-session shop APIs. No retry or redirect; callers own recovery.
class MerchantShopApi implements MerchantShopGateway {
  MerchantShopApi(this.config, this.access, {http.Client? client})
    : client = client ?? http.Client();
  final MerchantConfig config;
  final MerchantAccess access;
  final http.Client client;

  @override
  Future<ShopProfile> load() async =>
      _profile(await _send(http.Request('GET', _uri('/merchants/me'))));

  @override
  Future<ShopDashboard> dashboard() async {
    final data = await _send(
      http.Request('GET', _uri('/merchants/me/dashboard')),
    );
    if (data is! Map || data['today'] is! List || data['recent'] is! List) {
      throw const ShopFailure('INVALID_RESPONSE');
    }
    return _guardParse(
      () => ShopDashboard(
        profile: _profile(data['profile']),
        businessDate: data['businessDate'] as String,
        today: [
          for (final t in data['today'] as List)
            CurrencyTotal(
              t['currency'] as String,
              (t['count'] as num).toInt(),
              t['gross'] as String,
            ),
        ],
        recent: [
          for (final r in data['recent'] as List)
            ShopReceipt.fromJson(r as Map),
        ],
      ),
    );
  }

  @override
  Future<WalletPage> wallet(String accountNumber, {int page = 0}) async {
    if (!RegExp(r'^[0-9]{10,20}$').hasMatch(accountNumber)) {
      throw const ShopFailure('RESOURCE_NOT_FOUND', status: 404);
    }
    final data = await _send(
      http.Request(
        'GET',
        _uri('/merchants/me/wallets/$accountNumber')
            .replace(queryParameters: {'page': '$page'}),
      ),
    );
    return _guardParse(() {
      final w = data['wallet'] as Map;
      return WalletPage(
        ShopWallet(
          accountNumber: w['accountNumber'] as String,
          currency: w['currency'] as String,
          status: w['status'] as String,
          balance: w['balance'] as String,
        ),
        [
          for (final a in data['activity'] as List)
            WalletActivity(
              reference: a['reference'] as String,
              kind: a['kind'] as String,
              incoming: a['direction'] == 'IN',
              amount: a['amount'] as String,
              currency: a['currency'] as String,
              payerName: a['payerName'] as String?,
              payerAccount: a['payerAccount'] as String?,
              createdAt: DateTime.parse(a['createdAt'] as String),
            ),
        ],
        (data['page'] as num).toInt(),
        data['hasMore'] == true,
      );
    });
  }

  @override
  Future<ShopQr> shopQr(String currency) async {
    final data = await _send(
      http.Request(
        'GET',
        _uri('/merchants/me/qr')
            .replace(queryParameters: {'currency': currency}),
      ),
    );
    return _guardParse(
      () => ShopQr(
        qrString: data['qrString'] as String,
        currency: data['currency'] as String,
        accountNumber: data['accountNumber'] as String,
        storeName: data['storeName'] as String,
      ),
    );
  }

  @override
  Future<PaymentRequest> createRequest(
    String idempotencyKey, {
    required String currency,
    required String amount,
    String? orderReference,
  }) async {
    final request = http.Request('POST', _uri('/merchants/me/payment-requests'))
      ..headers['Content-Type'] = 'application/json'
      ..headers['Idempotency-Key'] = idempotencyKey
      ..body = jsonEncode({
        'currency': currency,
        'amount': amount,
        if (orderReference != null && orderReference.isNotEmpty)
          'orderReference': orderReference,
      });
    return _request(await _send(request));
  }

  @override
  Future<PaymentRequest> requestStatus(String id) async => _request(
    await _send(
      http.Request('GET', _uri('/merchants/me/payment-requests/${_id(id)}')),
    ),
  );

  @override
  Future<PaymentRequest> cancelRequest(String id) async => _request(
    await _send(
      http.Request(
        'POST',
        _uri('/merchants/me/payment-requests/${_id(id)}/cancel'),
      ),
    ),
  );

  static String _id(String id) {
    if (!RegExp(r'^[0-9a-f-]{36}$').hasMatch(id)) {
      throw const ShopFailure('RESOURCE_NOT_FOUND', status: 404);
    }
    return id;
  }

  static PaymentRequest _request(dynamic data) =>
      _guardParse(() => PaymentRequest.fromJson(data as Map));

  static T _guardParse<T>(T Function() parse) {
    try {
      return parse();
    } on ShopFailure {
      rethrow;
    } catch (_) {
      throw const ShopFailure('INVALID_RESPONSE');
    }
  }

  @override
  Future<ShopProfile> register(String idempotencyKey, ShopDraft draft) async {
    final request = http.Request('POST', _uri('/merchants/me/registration'))
      ..headers['Content-Type'] = 'application/json'
      ..headers['Idempotency-Key'] = idempotencyKey
      ..body = jsonEncode(draft.toJson());
    return _profile(await _send(request));
  }

  @override
  Future<ShopProfile> update(int version, Map<String, Object?> changes) async {
    final request = http.Request('PATCH', _uri('/merchants/me/profile'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({...changes, 'version': version});
    return _profile(await _send(request));
  }

  @override
  Future<String> uploadLogo(Uint8List bytes, String filename) async {
    // The server identifies the format by decoding it; the name carries no path.
    final request =
        http.MultipartRequest('POST', _uri('/merchants/me/logo-uploads'))
          ..files.add(
            http.MultipartFile.fromBytes(
              'logo',
              bytes,
              filename: filename.toLowerCase().endsWith('.png')
                  ? 'logo.png'
                  : 'logo.jpg',
            ),
          );
    final data = await _send(request);
    if (data is! Map || data['logoId'] is! String) {
      throw const ShopFailure('INVALID_RESPONSE');
    }
    return data['logoId'] as String;
  }

  @override
  Future<Uint8List?> logo() async {
    final token = await _token();
    try {
      final response = await client
          .get(
            _uri('/merchants/me/logo'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 404) return null;
      if (response.statusCode == 401) {
        throw const ShopFailure('SESSION_INVALID', status: 401);
      }
      if (response.statusCode != 200 ||
          !(response.headers['content-type'] ?? '').startsWith('image/')) {
        throw ShopFailure('REQUEST_FAILED', status: response.statusCode);
      }
      return response.bodyBytes;
    } on TimeoutException {
      throw const ShopFailure('TIMEOUT');
    } on http.ClientException {
      throw const ShopFailure('OFFLINE');
    }
  }

  Uri _uri(String path) => Uri.parse('${config.apiBaseUrl}$path');

  Future<String> _token() async {
    try {
      return await access.accessToken();
    } on MerchantAuthFailure catch (e) {
      throw ShopFailure(
        e.issue == MerchantAuthIssue.offline ? 'OFFLINE' : 'SESSION_INVALID',
        status: e.issue == MerchantAuthIssue.offline ? null : 401,
      );
    }
  }

  Future<dynamic> _send(http.BaseRequest request) async {
    request
      ..followRedirects = false
      ..headers['Accept'] = 'application/json'
      ..headers['Authorization'] = 'Bearer ${await _token()}';
    try {
      final response = await http.Response.fromStream(
        await client.send(request),
      ).timeout(const Duration(seconds: 20));
      dynamic envelope;
      try {
        envelope = jsonDecode(response.body);
      } catch (_) {
        throw ShopFailure('INVALID_RESPONSE', status: response.statusCode);
      }
      if (envelope is! Map) throw const ShopFailure('INVALID_RESPONSE');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ShopFailure(
          envelope['error'] is String ? envelope['error'] : 'REQUEST_FAILED',
          status: response.statusCode,
        );
      }
      if (envelope['success'] != true) {
        throw const ShopFailure('INVALID_RESPONSE');
      }
      return envelope['data'];
    } on TimeoutException {
      throw const ShopFailure('TIMEOUT');
    } on http.ClientException {
      throw const ShopFailure('OFFLINE');
    }
  }

  static ShopProfile _profile(dynamic data) {
    if (data is! Map ||
        data['onboardingState'] is! String ||
        data['owner'] is! Map ||
        data['wallets'] is! List) {
      throw const ShopFailure('INVALID_RESPONSE');
    }
    final shop = data['shop'];
    final state = data['onboardingState'] as String;
    if (['READY', 'RESTRICTED'].contains(state) && shop is! Map) {
      throw const ShopFailure('INVALID_RESPONSE');
    }
    return ShopProfile(
      onboardingState: state,
      ownerName: (data['owner'] as Map)['displayName'] as String? ?? '',
      shop: shop is Map
          ? ShopDetails(
              merchantId: shop['merchantId'] as String,
              storeName: shop['storeName'] as String,
              status: shop['status'] as String,
              version: (shop['version'] as num).toInt(),
              categoryCode: shop['categoryCode'] as String?,
              phone: shop['phone'] as String?,
              city: shop['city'] as String?,
              address: shop['address'] as String?,
              description: shop['description'] as String?,
              logoId: shop['logoId'] as String?,
            )
          : null,
      wallets: [
        for (final w in data['wallets'] as List)
          if (w is Map)
            ShopWallet(
              accountNumber: w['accountNumber'] as String,
              currency: w['currency'] as String,
              status: w['status'] as String,
              balance: w['balance'] as String,
            ),
      ],
    );
  }
}
