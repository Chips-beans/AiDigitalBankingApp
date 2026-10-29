import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/network/api_client.dart';

/// Only a matching callback for an active, locally initiated login can supply a code.
String nativeTelegramCode(String callback, String redirectUri, String flowId) {
  final uri = Uri.tryParse(callback);
  final expected = Uri.tryParse(redirectUri);
  if (uri == null ||
      expected == null ||
      expected.scheme != 'https' ||
      !expected.hasAuthority ||
      uri.scheme != 'https' ||
      uri.origin != expected.origin ||
      uri.path != expected.path ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      uri.queryParametersAll.values.any((values) => values.length != 1) ||
      uri.queryParameters['state'] != flowId) {
    throw const ApiFailure(
      'TELEGRAM_REJECTED',
      'Telegram returned an invalid login response.',
    );
  }
  if (uri.queryParameters.containsKey('error')) {
    throw ApiFailure(
      'TELEGRAM_CANCELLED',
      ApiFailure.messageFor('TELEGRAM_CANCELLED'),
    );
  }
  final code = uri.queryParameters['code'];
  if (code == null || code.trim().isEmpty || code.length > 4096) {
    throw const ApiFailure(
      'TELEGRAM_REJECTED',
      'Telegram returned an invalid login response.',
    );
  }
  return code;
}

class NativeTelegramClient {
  static const channel = MethodChannel('com.bank.customer_app/telegram_login');
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<String> authorize({
    required String authorizationUrl,
    required String redirectUri,
    required String flowId,
  }) async {
    try {
      final callback = await channel.invokeMethod<String>('authorize', {
        'authorizationUrl': authorizationUrl,
        'redirectUri': redirectUri,
        'flowId': flowId,
      });
      if (callback == null) {
        throw const ApiFailure(
          'TELEGRAM_REJECTED',
          'Telegram returned no login response.',
        );
      }
      return nativeTelegramCode(callback, redirectUri, flowId);
    } on PlatformException catch (error) {
      final code = error.code == 'TELEGRAM_CANCELLED'
          ? error.code
          : 'TELEGRAM_UNAVAILABLE';
      throw ApiFailure(code, ApiFailure.messageFor(code));
    } on MissingPluginException {
      throw const ApiFailure(
        'TELEGRAM_UNAVAILABLE',
        'Install the latest app build to use Telegram login.',
      );
    }
  }

  Future<void> cancel() async {
    try {
      await channel.invokeMethod<void>('cancel');
    } catch (_) {
      /* No active native bridge. */
    }
  }
}
