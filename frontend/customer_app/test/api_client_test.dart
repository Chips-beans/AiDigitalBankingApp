import 'dart:async';
import 'dart:convert';

import 'package:customer_app/core/config/app_config.dart';
import 'package:customer_app/core/network/api_client.dart';
import 'package:customer_app/features/auth/data/auth_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final config = AppConfig(
    apiBaseUrl: 'http://localhost:8080/api/v1',
    environment: 'dev',
  );
  test('public request has JSON but no bearer header; private read explicitly adds it', () async {
    final requests = <http.Request>[];
    final client = ApiClient(
      config,
      client: MockClient((r) async {
        requests.add(r);
        return http.Response('{"success":true,"data":{}}', 200);
      }),
    );
    addTearDown(client.close);
    await client.request(
      'POST',
      '/auth/request-otp',
      body: {'email': 'x@example.test', 'purpose': 'LOGIN'},
    );
    await client.request('GET', '/auth/me', accessToken: 'access');
    expect(
      requests[0].url.toString(),
      'http://localhost:8080/api/v1/auth/request-otp',
    );
    expect(requests[0].headers.containsKey('Authorization'), false);
    expect(jsonDecode(requests[0].body)['purpose'], 'LOGIN');
    expect(requests[1].headers['Authorization'], 'Bearer access');
    expect(requests.every((r) => !r.followRedirects), true);
  });
  test('structured field errors and Retry-After survive without reflecting raw server detail', () async {
    final client = ApiClient(
      config,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': false,
            'error': 'OTP_RATE_LIMITED',
            'message': 'private server detail',
            'fieldErrors': {'email': 'Invalid email'},
          }),
          429,
          headers: {'retry-after': '42'},
        ),
      ),
    );
    addTearDown(client.close);
    await expectLater(
      client.request('POST', '/auth/request-otp'),
      throwsA(
        isA<ApiFailure>()
            .having((e) => e.retryAfterSeconds, 'retry', 42)
            .having((e) => e.fields['email'], 'email', 'Invalid email')
            .having(
              (e) => e.message,
              'message',
              isNot(contains('private server detail')),
            ),
      ),
    );
  });
  test('timeout never automatically retries refresh', () async {
    var calls = 0;
    final response = Completer<http.Response>();
    final client = ApiClient(
      config,
      timeout: const Duration(milliseconds: 5),
      client: MockClient((_) {
        calls++;
        return response.future;
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.request('POST', '/auth/refresh', body: {'refreshToken': 'once'}),
      throwsA(isA<ApiFailure>().having((e) => e.code, 'code', 'TIMEOUT')),
    );
    expect(calls, 1);
    response.complete(http.Response('{"success":true}', 200));
  });
  test('network failure becomes a recoverable API failure', () async {
    final client = ApiClient(
      config,
      client: MockClient(
        (_) async => throw http.ClientException('Socket failure'),
      ),
    );
    addTearDown(client.close);
    await expectLater(
      client.request('GET', '/auth/me'),
      throwsA(isA<ApiFailure>().having((e) => e.code, 'code', 'OFFLINE')),
    );
  });
  test('malformed and unconfirmed responses fail closed', () async {
    for (final body in [
      '<html>Error</html>',
      '[]',
      '{"success":false}',
      '{"data":{}}',
    ]) {
      final client = ApiClient(
        config,
        client: MockClient((_) async => http.Response(body, 200)),
      );
      await expectLater(
        client.request('GET', '/auth/me'),
        throwsA(isA<ApiFailure>()),
      );
      client.close();
    }
  });
  test('external paths cannot redirect an authenticated request', () async {
    final client = ApiClient(config);
    addTearDown(client.close);
    for (final path in [
      'https://elsewhere.test',
      '//elsewhere.test',
      '/../auth/me',
      '/auth/me?other=1',
    ]) {
      await expectLater(
        client.request('GET', path, accessToken: 'private'),
        throwsArgumentError,
      );
    }
  });
  test('gateway rejects incomplete token/identity/OTP payloads', () {
    expect(
      () => TokenPair.fromJson({'accessToken': 'x'}),
      throwsA(isA<ApiFailure>()),
    );
    expect(
      () => SessionIdentity.fromJson({'userId': 1}),
      throwsA(isA<ApiFailure>()),
    );
    expect(
      () => OtpReceipt.fromJson({
        'expiresInSeconds': 0,
        'resendAfterSeconds': -1,
      }),
      throwsA(isA<ApiFailure>()),
    );
  });
  test('demo cannot be selected in production', () {
    expect(
      () => AppConfig(
        apiBaseUrl: 'https://bank.example/api/v1',
        environment: 'prod',
        mode: 'demo',
      ),
      throwsArgumentError,
    );
    expect(
      () => AppConfig(
        apiBaseUrl: config.apiBaseUrl,
        environment: 'dev',
        mode: 'invalid',
      ),
      throwsArgumentError,
    );
  });
}
