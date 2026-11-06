import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const merchantClient = 'kesor-merchant-android';
const approvalBase = 'kesorbank://merchant/approve';
const callbackBase = 'kesormerchant://auth/callback';

/// Owner transfers (M8) have their own exact links; they never share the sign-in paths.
const transferApprovalBase = 'kesorbank://merchant/transfer';
const transferCallbackBase = 'kesormerchant://transfer/callback';
const customerPackage = 'com.bank.customer_app';
const merchantPackage = 'com.bank.merchant_app';

String randomCredential() => base64Url
    .encode(List.generate(32, (_) => Random.secure().nextInt(256)))
    .replaceAll('=', '');
String challenge(String verifier) => base64Url
    .encode(sha256.convert(utf8.encode(verifier)).bytes)
    .replaceAll('=', '');
String secretHash(String secret) =>
    sha256.convert(utf8.encode(secret)).toString();
bool credential(String? value) =>
    value != null && RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value);
bool attemptId(String? value) =>
    value != null &&
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
        .hasMatch(value);
bool secureEquals(String a, String b) {
  var difference = a.length ^ b.length;
  for (var i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ (i < b.length ? b.codeUnitAt(i) : 0);
  }
  return difference == 0;
}

/// Reject alternate authorities, encoded paths, duplicate/unknown parameters and fragments.
Map<String, String> exactLink(String raw, String base, Set<String> keys) {
  final uri = Uri.tryParse(raw);
  if (raw.length > 2048 ||
      uri == null ||
      !raw.startsWith('$base?') ||
      uri.hasFragment ||
      uri.userInfo.isNotEmpty ||
      '${uri.scheme}://${uri.authority}${uri.path}' != base ||
      uri.queryParametersAll.length != keys.length ||
      uri.queryParametersAll.entries.any(
        (e) =>
            !keys.contains(e.key) ||
            e.value.length != 1 ||
            e.value.single.isEmpty,
      )) {
    throw const HandoffFailure('INVALID_LINK');
  }
  return uri.queryParameters;
}

class HandoffFailure implements Exception {
  const HandoffFailure(this.code, {this.status});
  final String code;
  final int? status;
  @override
  String toString() => code;
}

class NativeHandoff {
  const NativeHandoff();
  static const channel = MethodChannel('kesor/merchant_links');
  Future<String?> take() async {
    try {
      return await channel.invokeMethod<String>('take');
    } on MissingPluginException {
      return null;
    }
  }

  /// Transfer links use a separate native slot so a sign-in request is never confused with one.
  Future<String?> takeTransfer() async {
    try {
      return await channel.invokeMethod<String>('takeTransfer');
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> openTransfer(String uri) =>
      _invoke('openTransfer', {'uri': uri});
  Future<void> verify() => _invoke('verify');
  Future<void> open(String uri) => _invoke('open', {'uri': uri});
  Future<void> _invoke(String method, [Map<String, String>? arguments]) async {
    try {
      await channel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (e) {
      throw HandoffFailure(e.code);
    } on MissingPluginException {
      throw const HandoffFailure('HANDOFF_UNAVAILABLE');
    }
  }
}

abstract class HandoffStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class SecureHandoffStore implements HandoffStore {
  SecureHandoffStore(String namespace)
    : prefix = base64Url.encode(utf8.encode(namespace));
  final String prefix;
  final storage = const FlutterSecureStorage();
  @override
  Future<String?> read(String key) =>
      storage.read(key: 'kesor.handoff.$prefix.$key');
  @override
  Future<void> write(String key, String? value) => value == null
      ? storage.delete(key: 'kesor.handoff.$prefix.$key')
      : storage.write(key: 'kesor.handoff.$prefix.$key', value: value);
}

class MemoryHandoffStore implements HandoffStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

/// No retry, redirect, logging or implicit Bearer token. Callers own recovery.
class HandoffApi {
  HandoffApi(this.origin, {http.Client? client})
    : client = client ?? http.Client();
  final String origin;
  final http.Client client;
  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? access,
    String? handoff,
  }) async {
    if (!path.startsWith('/') ||
        path.contains('..') ||
        path.contains('?') ||
        path.startsWith('//'))
      throw ArgumentError('Invalid path');
    final req = http.Request(method, Uri.parse('$origin$path'))
      ..followRedirects = false;
    req.headers['Accept'] = 'application/json';
    if (access != null) req.headers['Authorization'] = 'Bearer $access';
    if (handoff != null) req.headers['X-Merchant-Handoff'] = handoff;
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    try {
      final response = await (() async => http.Response.fromStream(
        await client.send(req),
      ))().timeout(const Duration(seconds: 12));
      dynamic envelope;
      try {
        envelope = jsonDecode(response.body);
      } catch (_) {
        throw HandoffFailure('INVALID_RESPONSE', status: response.statusCode);
      }
      if (envelope is! Map) {
        throw HandoffFailure('INVALID_RESPONSE', status: response.statusCode);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HandoffFailure(
          envelope['error'] is String ? envelope['error'] : 'REQUEST_FAILED',
          status: response.statusCode,
        );
      }
      if (envelope['success'] != true) {
        throw HandoffFailure('INVALID_RESPONSE', status: response.statusCode);
      }
      return envelope['data'];
    } on TimeoutException {
      throw const HandoffFailure('TIMEOUT');
    } on http.ClientException {
      throw const HandoffFailure('OFFLINE');
    }
  }
}
