import 'package:flutter/foundation.dart';

/// Build-time configuration shared by future repositories and API clients.
class AppConfig {
  AppConfig({
    required this.apiBaseUrl,
    required this.environment,
    this.mode = 'api',
  }) {
    final uri = Uri.tryParse(apiBaseUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path != '/api/v1') {
      throw ArgumentError(
        'API_BASE_URL must be an http(s) URL ending in /api/v1',
      );
    }
    if (!{'dev', 'prod'}.contains(environment)) {
      throw ArgumentError('APP_ENV must be dev or prod');
    }
    if (environment == 'prod' && uri.scheme != 'https') {
      throw ArgumentError('Production API_BASE_URL must use HTTPS');
    }
    if (!{'api', 'demo'}.contains(mode) ||
        (environment == 'prod' && mode != 'api')) {
      throw ArgumentError('APP_MODE must be api; demo is allowed only in dev');
    }
  }

  factory AppConfig.fromEnvironment() {
    const override = String.fromEnvironment('API_BASE_URL');
    const environment = String.fromEnvironment(
      'APP_ENV',
      defaultValue: kReleaseMode ? 'prod' : 'dev',
    );
    final host = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : 'localhost';
    return AppConfig(
      apiBaseUrl: override.isEmpty ? 'http://$host:8080/api/v1' : override,
      environment: environment,
      mode: const String.fromEnvironment('APP_MODE', defaultValue: 'api'),
    );
  }

  final String apiBaseUrl;
  final String environment;
  final String mode;
  bool get isDemo => mode == 'demo';
}
