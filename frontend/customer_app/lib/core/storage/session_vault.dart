import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SessionVault {
  Future<String?> readRefreshToken();
  Future<void> writeRefreshToken(String? token);
  Future<String> installationId();
}

/// The only persisted auth material is the rotating refresh token and an installation ID.
/// Default Android ciphers use the Keystore without biometric authentication.
class SecureSessionVault implements SessionVault {
  SecureSessionVault(String namespace, {FlutterSecureStorage? storage})
    : _prefix = 'banking.v1.${base64Url.encode(utf8.encode(namespace))}',
      _storage = storage ?? const FlutterSecureStorage();
  final String _prefix;
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readRefreshToken() => _storage.read(key: '$_prefix.refresh');
  @override
  Future<void> writeRefreshToken(String? token) => token == null
      ? _storage.delete(key: '$_prefix.refresh')
      : _storage.write(key: '$_prefix.refresh', value: token);
  @override
  Future<String> installationId() async {
    final existing = await _storage.read(key: '$_prefix.installation');
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final id = List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await _storage.write(key: '$_prefix.installation', value: id);
    return id;
  }
}

/// Used explicitly for browser previews/tests; never a fallback for failed native storage.
class MemorySessionVault implements SessionVault {
  String? refreshToken;
  String? _id;
  @override
  Future<String?> readRefreshToken() async => refreshToken;
  @override
  Future<void> writeRefreshToken(String? token) async {
    refreshToken = token;
  }

  @override
  Future<String> installationId() async {
    if (_id != null) return _id!;
    // Avoid large integer shifts: JavaScript and VM integer representations differ.
    final random = Random.secure();
    _id =
        'browser-${List.generate(24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    return _id!;
  }
}
