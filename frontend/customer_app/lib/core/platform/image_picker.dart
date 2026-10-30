import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../network/api_client.dart';

const _channel = MethodChannel('com.bank.customer_app/image_picker');

/// Picks one JPG or PNG. On Android the retained-engine bridge survives the host
/// Activity being destroyed while the picker is open (which loses `file_selector`
/// results on devices with "Don't keep activities"). Returns null when cancelled.
Future<XFile?> pickImageFile() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final path = await _channel.invokeMethod<String>('pickImage');
      return path == null ? null : XFile(path);
    } on PlatformException catch (e) {
      throw ApiFailure(
        'IMAGE_${e.code}',
        e.message ?? 'The image could not be opened.',
      );
    }
  }
  return openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'JPG or PNG',
        extensions: ['jpg', 'jpeg', 'png'],
        mimeTypes: ['image/jpeg', 'image/png'],
        uniformTypeIdentifiers: ['public.jpeg', 'public.png'],
      ),
    ],
  );
}
