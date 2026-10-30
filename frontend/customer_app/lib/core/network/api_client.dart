import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'exact_json.dart';

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
    'AI_UNAVAILABLE' =>
      'The assistant is unavailable. Your banking services remain available.',
    'AI_STORAGE' =>
      'The saved question could not be read or saved. Sending is blocked.',
    'AI_INVALID_RESPONSE' => 'The assistant response could not be verified.',
    'AI_SENSITIVE_INPUT' =>
      'Do not send PINs, OTPs, passwords or authentication tokens.',
    'AI_RATE_LIMITED' || 'AI_PROVIDER_RATE_LIMITED' =>
      'Assistant request limit reached. Try again later.',
    'AI_BUSY' ||
    'AI_REQUEST_IN_PROGRESS' => 'The assistant is busy. Try again shortly.',
    'AI_TIMEOUT' =>
      'The assistant timed out. Check the saved request before retrying.',
    'AI_REQUEST_INTERRUPTED' =>
      'This assistant request was interrupted. Retry explicitly to ask again.',
    'AI_IDEMPOTENCY_CONFLICT' =>
      'This request key belongs to a different assistant request.',
    'UNSUPPORTED_QR' ||
    'INVALID_QR_CODE' ||
    'INVALID_QR_FORMAT' ||
    'INVALID_QR_CHECKSUM' ||
    'INVALID_QR_DATA' ||
    'INVALID_QR_AMOUNT' => 'Only registered Kesor QR codes are supported.',
    'PAYMENT_ALREADY_COMPLETED' => 'This request has already been paid.',
    'AMOUNT_MISMATCH' => 'The amount does not match this QR request.',
    'PIN_REQUIRED' => 'Unlock the app with your PIN.',
    'PIN_INVALID' => 'Incorrect PIN. Please try again.',
    'PIN_RECOVERY_REQUIRED' =>
      'Five incorrect attempts. Verify your identity to reset your PIN.',
    'PIN_RECOVERY_AUTH_REQUIRED' =>
      'Verify your email or Telegram again to reset your PIN.',
    'PIN_TICKET_INVALID' => 'Your app session has ended. Sign in again.',
    'PIN_SETUP_REQUIRED' => 'Create your PIN to continue.',
    'PIN_CONFIRMATION_MISMATCH' =>
      'The PINs do not match. Try confirming again.',
    'TELEGRAM_CANCELLED' =>
      'Telegram approval was cancelled. Try again or continue with email.',
    'TELEGRAM_UNAVAILABLE' =>
      'Telegram is temporarily unavailable. Try again or continue with email.',
    'TELEGRAM_REJECTED' =>
      'Telegram approval could not be verified. Please try again.',
    'TELEGRAM_FLOW_INVALID' =>
      'Telegram approval expired or was already used. Please try again.',
    'FRESH_AUTH_REQUIRED' =>
      'Continue again before connecting Telegram to your profile.',
    'IDENTITY_ALREADY_LINKED' => 'This identity is already connected to a profile. Use that profile to continue.',
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
    'PROFILE_PHOTO_INVALID' =>
      'Choose a valid JPG or PNG up to 5 MB and 16 megapixels.',
    'PROFILE_PHOTO_TOO_LARGE' => 'Choose a JPG or PNG up to 5 MB.',
    'INSUFFICIENT_FUNDS' => 'There are not enough funds in the source account.',
    'ACCOUNT_INACTIVE' => 'Both accounts must be active to make a transfer.',
    'CURRENCY_MISMATCH' => 'Both accounts must use the transfer currency.',
    'INVALID_AMOUNT' => 'Enter a positive amount within the currency precision and supported range.',
    'RESOURCE_NOT_FOUND' =>
      'The requested account or transaction is unavailable.',
    'IDEMPOTENCY_CONFLICT' => 'The saved transfer conflicts with an earlier request. Keep this record and contact support; do not create another transfer to retry it.',
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
    Map<String, String>? query,
    int? expectedStatus,
    String? idempotencyKey,
    String? pinProof,
    List<int>? photoBytes,
  }) async {
    if (!path.startsWith('/') ||
        path.startsWith('//') ||
        path.contains('..') ||
        path.contains('?')) {
      throw ArgumentError('Use an API-relative path');
    }
    final uri = Uri.parse('${config.apiBaseUrl}$path')
        .replace(queryParameters: query);
    final http.BaseRequest request;
    if (photoBytes != null) {
      request = http.MultipartRequest(method, uri)
        ..files.add(
          http.MultipartFile.fromBytes(
            'photo',
            photoBytes,
            filename: 'profile-photo',
          ),
        );
    } else {
      request = http.Request(method, uri);
    }
    request.followRedirects = false;
    request.headers['Accept'] = 'application/json';
    if (accessToken != null) {
      request.headers['Authorization'] = 'Bearer $accessToken';
    }
    if (idempotencyKey != null) {
      request.headers['Idempotency-Key'] = idempotencyKey;
    }
    if (pinProof != null) request.headers['X-Pin-Proof'] = pinProof;
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      (request as http.Request).body = jsonEncode(body);
    }
    try {
      final response = await (() async => http.Response.fromStream(
        await _client.send(request),
      ))().timeout(timeout);
      Map<String, dynamic> payload;
      try {
        final decoded = decodeExactJson(response.body);
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
      if (expectedStatus != null && response.statusCode != expectedStatus) {
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
