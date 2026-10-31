package com.bank.customer_app

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
        // Android can recreate this Activity on return (including with the
        // developer "Don't keep activities" setting enabled). Reuse the same
        // engine/bridge, and deliver the callback from the initial Intent too.
        kesor.telegram.handleIntent(intent)
        kesor.merchant.handleIntent(intent)
        setIntent(Intent(intent).setData(null))
        kesor.imagePicker.activity = this
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        kesor.telegram.handleIntent(intent)
        kesor.merchant.handleIntent(intent)
        setIntent(Intent(intent).setData(null))
    }

    override fun onResume() {
        super.onResume()
        kesor.imagePicker.activity = this
        kesor.share.activity = this
    }

    override fun onDestroy() {
        if (kesor.imagePicker.activity === this) kesor.imagePicker.activity = null
        if (kesor.share.activity === this) kesor.share.activity = null
        super.onDestroy()
    }

    @Deprecated("Activity result API is not used by the retained-engine bridges")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // A recreated Activity still receives the picker result; the bridge owns the pending call.
        if (!kesor.imagePicker.onActivityResult(requestCode, resultCode, data)) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}
