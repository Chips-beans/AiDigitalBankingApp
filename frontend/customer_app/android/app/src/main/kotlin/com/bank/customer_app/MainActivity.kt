package com.bank.customer_app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var telegram: TelegramLoginBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val bridge = TelegramLoginBridge(this)
        telegram = bridge
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.bank.customer_app/telegram_login")
            .setMethodCallHandler(bridge)
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        telegram?.handleIntent(intent)
    }
    override fun onDestroy() {
        telegram?.dispose()
        telegram = null
        super.onDestroy()
    }
}
