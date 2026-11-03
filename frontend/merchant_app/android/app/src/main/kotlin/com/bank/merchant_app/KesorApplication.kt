package com.bank.merchant_app

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class KesorApplication : Application() {
    lateinit var merchant: MerchantLinkBridge
        private set
    lateinit var share: ShareBridge
        private set
    val flutterEngine: FlutterEngine by lazy {
        FlutterEngine(this).also { engine ->
            merchant = MerchantLinkBridge(this)
            MethodChannel(engine.dartExecutor.binaryMessenger, "kesor/merchant_links")
                .setMethodCallHandler(merchant)
            share = ShareBridge(this)
            MethodChannel(engine.dartExecutor.binaryMessenger, "kesor/merchant_share")
                .setMethodCallHandler(share)
            engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        }
    }
}
