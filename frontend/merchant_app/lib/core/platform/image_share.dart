import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../features/shop/merchant_shop.dart';
import '../../features/shop/shop_widgets.dart';
import '../merchant_strings.dart';

const merchantShareChannel = MethodChannel('kesor/merchant_share');
bool get imageShareSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

Future<void> saveImageToGallery(Uint8List png, String name) =>
    _call('saveImage', {'png': png, 'name': name});
Future<void> shareImage(
  Uint8List png,
  String name, {
  String? text,
  String? title,
}) => _call('shareImage', {
  'png': png,
  'name': name,
  'text': text,
  'title': title,
});
Future<void> _call(String method, Map<String, Object?> args) async {
  if (!imageShareSupported) throw const ShopFailure('SHARE_UNSUPPORTED');
  try {
    if (await merchantShareChannel.invokeMethod<bool>(method, args) != true) {
      throw const ShopFailure('SHARE_UNAVAILABLE');
    }
  } on PlatformException catch (e) {
    throw ShopFailure('SHARE_${e.code}');
  } on MissingPluginException {
    throw const ShopFailure('SHARE_UNAVAILABLE');
  }
}

/// Capture only the explicit public card; no navigation/session state is shared.
Future<Uint8List> captureCard(GlobalKey key) async {
  final boundary = key.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) {
    throw const ShopFailure('SHARE_UNAVAILABLE');
  }
  final image = await boundary.toImage(pixelRatio: 2);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw const ShopFailure('SHARE_UNAVAILABLE');
    return bytes.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

String shareFailureMessage(BuildContext context, ShopFailure failure) =>
    switch (failure.code) {
      'SHARE_APP_UNAVAILABLE' => t(
        context,
        'No app is available to share images.',
        'គ្មានកម្មវិធីសម្រាប់ចែករំលែករូបភាពទេ។',
      ),
      'SHARE_UNSUPPORTED_ANDROID' => t(
        context,
        'Saving to gallery needs Android 10 or newer. You can still share the image.',
        'ការរក្សាទុកក្នុងវិចិត្រសាលត្រូវការ Android 10 ឬថ្មីជាងនេះ។ អ្នកនៅតែអាចចែករំលែករូបភាពបាន។',
      ),
      'SHARE_UNSUPPORTED' => t(
        context,
        'Saving and sharing are available in the Android app.',
        'ការរក្សាទុក និងចែករំលែកអាចប្រើបានក្នុងកម្មវិធី Android។',
      ),
      _ => t(
        context,
        'The image could not be saved or shared. Please try again.',
        'មិនអាចរក្សាទុក ឬចែករំលែករូបភាពបានទេ។ សូមព្យាយាមម្ដងទៀត។',
      ),
    };

class ImageActions extends StatefulWidget {
  const ImageActions({
    required this.cardKey,
    required this.name,
    this.text,
    this.receipt = false,
    this.capture = captureCard,
    super.key,
  });
  final GlobalKey cardKey;
  final String name;
  final String? text;
  final bool receipt;
  final Future<Uint8List> Function(GlobalKey) capture;
  @override
  State<ImageActions> createState() => _ImageActionsState();
}

class _ImageActionsState extends State<ImageActions> {
  bool busy = false;
  ShopFailure? failure;
  Future<void> act(bool save) async {
    if (busy) return;
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      final title = t(
        context,
        widget.receipt ? 'Share receipt' : 'Share QR code',
        widget.receipt ? 'ចែករំលែកបង្កាន់ដៃ' : 'ចែករំលែកកូដ QR',
      );
      final png = await widget.capture(widget.cardKey);
      if (!mounted) return;
      if (save) {
        await saveImageToGallery(png, widget.name);
      } else {
        await shareImage(png, widget.name, text: widget.text, title: title);
      }
      if (save && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(context, 'Saved to gallery', 'បានរក្សាទុកក្នុងវិចិត្រសាល'),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => failure = e is ShopFailure
              ? e
              : const ShopFailure('SHARE_UNAVAILABLE'),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (failure != null) ...[
        NoticeBanner(
          shareFailureMessage(context, failure!),
          tone: NoticeTone.error,
        ),
        const SizedBox(height: 12),
      ],
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: OutlinedButton(
              key: const ValueKey('save-image'),
              onPressed: busy ? null : () => act(true),
              child: Text(
                t(context, 'Save to gallery', 'រក្សាទុកក្នុងវិចិត្រសាល'),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              key: const ValueKey('share-image'),
              onPressed: busy ? null : () => act(false),
              child: Text(
                t(
                  context,
                  widget.receipt ? 'Share receipt' : 'Share',
                  'ចែករំលែក',
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
      if (busy) const LinearProgressIndicator(),
    ],
  );
}
