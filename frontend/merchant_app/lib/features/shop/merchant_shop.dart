import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../collect/merchant_collect.dart';

/// Server allowlist (M4). Labels are local; only the code is sent.
@immutable
class ShopCategory {
  const ShopCategory(this.code, this.en, this.km, this.icon);
  final String code, en, km;
  final IconData icon;
}

const shopCategories = [
  ShopCategory(
    'FOOD_DRINK',
    'Food & drinks',
    'អាហារ និងភេសជ្ជៈ',
    Icons.local_cafe_outlined,
  ),
  ShopCategory(
    'GROCERY',
    'Grocery',
    'គ្រឿងទេស',
    Icons.local_grocery_store_outlined,
  ),
  ShopCategory('RETAIL', 'Retail', 'លក់រាយ', Icons.storefront_outlined),
  ShopCategory('FASHION', 'Fashion', 'សម្លៀកបំពាក់', Icons.checkroom_outlined),
  ShopCategory('BEAUTY', 'Beauty & salon', 'សម្ផស្ស', Icons.spa_outlined),
  ShopCategory(
    'ELECTRONICS',
    'Electronics',
    'គ្រឿងអេឡិចត្រូនិក',
    Icons.devices_other_outlined,
  ),
  ShopCategory(
    'HEALTH',
    'Health & pharmacy',
    'សុខភាព និងឱសថ',
    Icons.local_pharmacy_outlined,
  ),
  ShopCategory('SERVICES', 'Services', 'សេវាកម្ម', Icons.handyman_outlined),
  ShopCategory('EDUCATION', 'Education', 'ការអប់រំ', Icons.school_outlined),
  ShopCategory(
    'TRANSPORT',
    'Transport',
    'ដឹកជញ្ជូន',
    Icons.local_shipping_outlined,
  ),
  ShopCategory('OTHER', 'Other', 'ផ្សេងៗ', Icons.category_outlined),
];

ShopCategory? categoryFor(String? code) {
  for (final category in shopCategories) {
    if (category.code == code) return category;
  }
  return null;
}

@immutable
class ShopWallet {
  const ShopWallet({
    required this.accountNumber,
    required this.currency,
    required this.status,
    required this.balance,
  });
  final String accountNumber, currency, status;

  /// Exact decimal text from the server; never parsed into a double.
  final String balance;
}

@immutable
class ShopDetails {
  const ShopDetails({
    required this.merchantId,
    required this.storeName,
    required this.status,
    required this.version,
    this.categoryCode,
    this.phone,
    this.city,
    this.address,
    this.description,
    this.logoId,
  });
  final String merchantId, storeName, status;
  final String? categoryCode, phone, city, address, description, logoId;
  final int version;
  bool get active => status == 'ACTIVE';
}

@immutable
class ShopProfile {
  const ShopProfile({
    required this.onboardingState,
    required this.ownerName,
    this.shop,
    this.wallets = const [],
  });
  final String onboardingState, ownerName;
  final ShopDetails? shop;
  final List<ShopWallet> wallets;
}

/// Immutable registration intent. Saved with its key before it is sent.
@immutable
class ShopDraft {
  const ShopDraft({
    required this.storeName,
    required this.categoryCode,
    required this.phone,
    required this.city,
    required this.address,
    this.description = '',
    this.logoId,
  });
  final String storeName, categoryCode, phone, city, address, description;
  final String? logoId;

  Map<String, Object?> toJson() => {
    'storeName': storeName,
    'categoryCode': categoryCode,
    'phone': phone,
    'city': city,
    'address': address,
    if (description.isNotEmpty) 'description': description,
    if (logoId != null) 'stagedLogoId': logoId,
  };

  static ShopDraft fromJson(Map<String, dynamic> json) => ShopDraft(
    storeName: json['storeName'] as String,
    categoryCode: json['categoryCode'] as String,
    phone: json['phone'] as String,
    city: json['city'] as String,
    address: json['address'] as String,
    description: json['description'] as String? ?? '',
    logoId: json['stagedLogoId'] as String?,
  );
}

class ShopFailure implements Exception {
  const ShopFailure(this.code, {this.status});
  final String code;
  final int? status;

  /// The server may have completed the request; never resend automatically.
  bool get uncertain =>
      const {'OFFLINE', 'TIMEOUT', 'INVALID_RESPONSE'}.contains(code) ||
      (status ?? 0) >= 500;
  bool get expired =>
      status == 401 ||
      const {
        'SESSION_INVALID',
        'TOKEN_INVALID',
        'SESSION_EXPIRED',
      }.contains(code);
  @override
  String toString() => code;
}

/// All Merchant-session shop APIs; the collection half is [MerchantCollectGateway].
abstract interface class MerchantShopGateway implements MerchantCollectGateway {
  Future<ShopProfile> load();
  Future<ShopProfile> register(String idempotencyKey, ShopDraft draft);
  Future<ShopProfile> update(int version, Map<String, Object?> changes);

  /// Returns the server's staged logo ID.
  Future<String> uploadLogo(Uint8List bytes, String filename);
  Future<Uint8List?> logo();
}
