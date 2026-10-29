import 'package:web/web.dart' as web;

import 'dart:convert';
import 'dart:js_interop';

class TelegramWindow {
  TelegramWindow() {
    _listener = ((web.MessageEvent event) {
      try {
        // Dart's overloaded equality can inspect properties forbidden on cross-origin WindowProxy objects.
        // The JavaScript identity operator compares the references without reading either window.
        if (event.origin != _callbackOrigin ||
            !event.source.strictEquals(_window).toDart) {
          return;
        }
        final raw = event.data.dartify();
        if (raw is! String) return;
        final data = jsonDecode(raw);
        if (data is Map &&
            data['type'] == 'kesor.telegram.approved' &&
            data['flowId'] == _flowId &&
            data['approvalReceipt'] is String &&
            RegExp(r'^[A-Za-z0-9_-]{43}$')
                .hasMatch(data['approvalReceipt'] as String)) {
          _receipt = data['approvalReceipt'] as String;
        }
      } catch (_) {
        /* Ignore messages from unrelated windows. */
      }
    }).toJS;
    web.window.addEventListener('message', _listener);
  }
  late final JSFunction _listener;
  String? _flowId, _callbackOrigin, _receipt;
  String? get approvalReceipt => _receipt;
  void configure(String flowId, String callbackOrigin) {
    _flowId = flowId;
    _callbackOrigin = callbackOrigin;
  }

  // Open synchronously from the user's click, before requesting the authorization URL.
  final web.Window? _window = web.window.open(
    'about:blank',
    '_blank',
    'popup,width=480,height=720',
  );
  bool get available => _window != null;
  void navigate(String url) {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' ||
        uri.host != 'oauth.telegram.org' ||
        uri.path != '/auth') {
      throw const FormatException('Unexpected Telegram authorization URL');
    }
    _window?.location.href = url;
  }

  void close() {
    web.window.removeEventListener('message', _listener);
    try {
      _window?.close();
    } catch (_) {
      /* The provider may isolate its window. */
    }
  }
}
