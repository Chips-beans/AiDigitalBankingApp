import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'support_email_stub.dart'
    if (dart.library.js_interop) 'support_email_web.dart';

class SettingsPlatform {
  static const channel = MethodChannel('com.bank.customer_app/settings');
  bool get supportsNotifications =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<bool> notificationsEnabled() async =>
      supportsNotifications &&
      (await channel.invokeMethod<bool>('notificationsEnabled') ?? false);
  Future<void> openNotifications() async {
    await channel.invokeMethod<bool>('openNotifications');
  }

  Future<bool> activityAlert() async =>
      supportsNotifications &&
      (await channel.invokeMethod<bool>('activityAlert') ?? false);
  Future<bool> emailSupport() async {
    if (kIsWeb) return openSupportEmail();
    if (!supportsNotifications) return false;
    return await channel.invokeMethod<bool>('emailSupport') ?? false;
  }
}
