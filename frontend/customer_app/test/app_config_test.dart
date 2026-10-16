import 'package:customer_app/core/config/app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'Android development configuration reaches the host API through its alias',
    () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        AppConfig.fromEnvironment().apiBaseUrl,
        'http://10.0.2.2:8080/api/v1',
      );
    },
  );

  test('desktop development configuration uses localhost', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(
      AppConfig.fromEnvironment().apiBaseUrl,
      'http://localhost:8080/api/v1',
    );
  });

  test('a physical device can use a configured LAN endpoint', () {
    final config = AppConfig(
      apiBaseUrl: 'http://192.168.1.25:8080/api/v1',
      environment: 'dev',
    );
    expect(config.apiBaseUrl, contains('192.168.1.25'));
  });

  test('production requires HTTPS and an explicit usable endpoint', () {
    expect(
      () => AppConfig(
        apiBaseUrl: 'http://localhost:8080/api/v1',
        environment: 'prod',
      ),
      throwsArgumentError,
    );
    expect(
      AppConfig(
        apiBaseUrl: 'https://api.example.test/api/v1',
        environment: 'prod',
      ).environment,
      'prod',
    );
  });

  test('invalid configuration fails early', () {
    for (final url in [
      'not a URL',
      'ftp://example.test/api/v1',
      'https://example.test/wrong',
      'https://name:secret@example.test/api/v1',
      'https://example.test/api/v1?token=secret',
    ]) {
      expect(
        () => AppConfig(apiBaseUrl: url, environment: 'dev'),
        throwsArgumentError,
      );
    }
    expect(
      () => AppConfig(
        apiBaseUrl: 'https://example.test/api/v1',
        environment: 'unknown',
      ),
      throwsArgumentError,
    );
  });
}
