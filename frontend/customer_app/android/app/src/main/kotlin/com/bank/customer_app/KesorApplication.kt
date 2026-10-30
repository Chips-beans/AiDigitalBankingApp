package com.bank.customer_app

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/** One in-process session survives Android recreating its host Activity.
 * The normal Dart lifecycle still locks banking on background. Nothing here
 * persists pending login secrets or accepts an unsolicited cold-start callback.
 */
class KesorApplication : Application() {
    lateinit var telegram: TelegramLoginBridge
        private set
    lateinit var imagePicker: ImagePickerBridge
        private set
    lateinit var share: ShareBridge
        private set

    val flutterEngine: FlutterEngine by lazy {
        FlutterEngine(this).also { engine ->
            telegram = TelegramLoginBridge(this)
            imagePicker = ImagePickerBridge(this)
            MethodChannel(engine.dartExecutor.binaryMessenger, "com.bank.customer_app/image_picker")
                .setMethodCallHandler(imagePicker)
            share = ShareBridge(this)
            MethodChannel(engine.dartExecutor.binaryMessenger, "com.bank.customer_app/share")
                .setMethodCallHandler(share)
            MethodChannel(engine.dartExecutor.binaryMessenger, "com.bank.customer_app/settings")
                .setMethodCallHandler(SettingsBridge(this))
            MethodChannel(engine.dartExecutor.binaryMessenger, "com.bank.customer_app/telegram_login")
                .setMethodCallHandler(telegram)
            engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        }
    }
}
