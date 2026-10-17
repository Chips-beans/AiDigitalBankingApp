import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class ApiFailure implements Exception {
  const ApiFailure(
    this.code,
    this.message, {
    this.status,
    this.fields = const {},
    this.retryAfterSeconds,
  });
  final String code;
  final String message;
  final int? status;
  final Map<String, String> fields;
  final int? retryAfterSeconds;
  @override
  String toString() => '$code: $message';

  static String messageFor(String code) => switch (code) {
    'AUTHENTICATION_FAILED' =>
      'Your email or password did not match. Go back to check your details.',
    'OTP_INVALID' =>
      'That code did not match. Check the latest email and try again.',
    'OTP_EXPIRED' => 'This code has expired. Request a new code.',
    'OTP_USED' => 'This code has already been used. Request a new code.',
    'OTP_ATTEMPTS_EXCEEDED' => 'Too many incorrect codes. Request a new code.',
    'OTP_RATE_LIMITED' => 'Please wait before requesting another code.',
    'LOGIN_RATE_LIMITED' =>
      'Too many sign-in attempts. Please wait and try again.',
    'IDENTITY_UNAVAILABLE' =>
      'That username or email is already in use. Try signing in.',
    'OTP_DELIVERY_UNAVAILABLE' =>
      'We could not send your code. Please try again shortly.',
    'USER_DISABLED' => 'This profile is disabled. Contact your bank for help.',
    'DEVICE_REVOKED' =>
      'This installation no longer has access. Contact your bank for help.',
    'TOKEN_INVALID' ||
    'SESSION_INVALID' ||
    'REFRESH_REUSED' ||
    'AUTHENTICATION_REQUIRED' =>
      'Your session has ended. Please sign in again.',
    'VALIDATION_FAILED' ||
    'INVALID_REQUEST' => 'Please check the highlighted details.',
    'ACCESS_DENIED' => 'This action is not available for your profile.',
    'AUDIT_UNAVAILABLE' =>
      'The service is temporarily unavailable. Please try again shortly.',
    _ => 'We could not complete this request. Please try again.',
  };
}

/// One request, one response. Financial/auth mutations are never retried here.
class ApiClient {
  ApiClient(
    this.config, {
    http.Client? client,
    this.timeout = const Duration(seconds: 12),
  }) : _client = client ?? http.Client();
  final AppConfig config;
  final http.Client _client;
  final Duration timeout;

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
  }) async {
    if (!path.startsWith('/') ||
        path.startsWith('//') ||
        path.contains('..') ||
        path.contains('?')) {
      throw ArgumentError('Use an API-relative path');
    }
    final request = http.Request(method, Uri.parse('${config.apiBaseUrl}$path'))
      ..followRedirects = false
      ..headers['Accept'] = 'application/json';
    if (accessToken != null) {
      request.headers['Authorization'] = 'Bearer $accessToken';
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final response = await (() async => http.Response.fromStream(
        await _client.send(request),
      ))().timeout(timeout);
      Map<String, dynamic> payload;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) throw const FormatException();
        payload = decoded;
      } on FormatException {
        throw const ApiFailure(
          'INVALID_RESPONSE',
          'The service returned an unreadable response. Try again shortly.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final code = payload['error'] is String
            ? payload['error'] as String
            : 'REQUEST_FAILED';
        final fields = <String, String>{};
        if (payload['fieldErrors'] case final Map errors) {
          for (final entry in errors.entries) {
            if (entry.key is String && entry.value is String) {
              fields[entry.key as String] = entry.value as String;
            }
          }
        }
        final retry =
            payload['retryAfterSeconds'] ??
            int.tryParse(response.headers['retry-after'] ?? '');
        throw ApiFailure(
          code,
          ApiFailure.messageFor(code),
          status: response.statusCode,
          fields: fields,
          retryAfterSeconds: retry is int && retry > 0 ? retry : null,
        );
      }
      if (payload['success'] != true) {
        throw const ApiFailure(
          'INVALID_RESPONSE',
          'The service could not confirm this request.',
        );
      }
      return payload;
    } on TimeoutException {
      throw const ApiFailure(
        'TIMEOUT',
        'The request took too long. Check your connection and try again.',
      );
    } on http.ClientException {
      throw const ApiFailure(
        'OFFLINE',
        'Cannot reach the service. Check your connection and try again.',
      );
    }
  }

  void close() => _client.close();
}
