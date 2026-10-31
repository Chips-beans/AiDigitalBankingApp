import 'package:flutter/foundation.dart';

class MerchantConfig {
  MerchantConfig({required this.apiBaseUrl, required this.environment}) {
    final uri = Uri.tryParse(apiBaseUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path != '/api/v1' ||
        !{'dev', 'prod'}.contains(environment) ||
        (environment == 'prod' && uri.scheme != 'https')) {
      throw ArgumentError('Invalid Merchant API configuration');
    }
  }

  factory MerchantConfig.fromEnvironment() {
    const environment = String.fromEnvironment(
      'APP_ENV',
      defaultValue: kReleaseMode ? 'prod' : 'dev',
    );
    const override = String.fromEnvironment('API_BASE_URL');
    return MerchantConfig(
      apiBaseUrl: override.isNotEmpty
          ? override
          : 'http://${!kIsWeb && defaultTargetPlatform == TargetPlatform.android ? '10.0.2.2' : 'localhost'}:8080/api/v1',
      environment: environment,
    );
  }

  final String apiBaseUrl, environment;
  static const clientId = 'kesor-merchant-android';
  static const androidPackage = 'com.bank.merchant_app';
  static const customerPackage = 'com.bank.customer_app';
  static const developmentApprovalUri = 'kesorbank://merchant/approve';
  static const developmentCallbackUri = 'kesormerchant://auth/callback';

  String get storageNamespace => 'kesor.merchant.v1|$apiBaseUrl';
}
