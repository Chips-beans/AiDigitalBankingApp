package com.bank.merchant_app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private val kesor get() = application as KesorApplication
    override fun provideFlutterEngine(context: Context): FlutterEngine = kesor.flutterEngine
    override fun shouldDestroyEngineWithHost(): Boolean = false
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        kesor.merchant.handleIntent(intent)
        setIntent(Intent(intent).setData(null))
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        kesor.merchant.handleIntent(intent)
        setIntent(Intent(intent).setData(null))
    }
}
