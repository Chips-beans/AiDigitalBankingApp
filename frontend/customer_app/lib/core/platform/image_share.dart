import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../network/api_client.dart';

const _channel = MethodChannel('com.bank.customer_app/share');

bool get imageShareSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Saves a PNG the user asked to keep into Pictures/Kesor Bank.
Future<void> saveImageToGallery(Uint8List png, String name) =>
    _call('saveImage', {'png': png, 'name': name});

/// Opens the system share sheet for a PNG the user asked to share.
Future<void> shareImage(Uint8List png, String name, {String? text}) =>
    _call('shareImage', {'png': png, 'name': name, 'text': text});

Future<void> _call(String method, Map<String, Object?> arguments) async {
  if (!imageShareSupported) {
    throw const ApiFailure(
      'UNSUPPORTED',
      'Saving and sharing are available in the Android app.',
    );
  }
  try {
    final ok = await _channel.invokeMethod<bool>(method, arguments);
    if (ok == false) throw PlatformException(code: 'UNAVAILABLE');
  } on PlatformException catch (e) {
    throw ApiFailure(
      'SHARE_${e.code}',
      e.message ?? 'The QR image could not be saved or shared.',
    );
  }
}
