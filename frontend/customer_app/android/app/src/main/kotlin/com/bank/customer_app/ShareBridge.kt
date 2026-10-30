package com.bank.customer_app

import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Saves or shares a rendered PNG (the customer's own receive-QR card) that the user
 * explicitly asked to save or share. Nothing is sent anywhere by this bridge itself.
 */
class ShareBridge(private val context: Context) : MethodChannel.MethodCallHandler {
    var activity: Activity? = null
    private val maxBytes = 8 * 1024 * 1024

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("png")
        val name = (call.argument<String>("name") ?: "kesor-qr").replace(Regex("[^A-Za-z0-9_-]"), "_").take(60)
        if (bytes == null || bytes.isEmpty() || bytes.size > maxBytes ||
            !(bytes.size > 8 && bytes[0] == 0x89.toByte() && bytes[1] == 0x50.toByte())) {
            result.error("INVALID_IMAGE", "The QR image could not be prepared.", null); return
        }
        try {
            when (call.method) {
                "saveImage" -> result.success(save(bytes, name))
                "shareImage" -> { share(bytes, name, call.argument<String>("text")); result.success(true) }
                else -> result.notImplemented()
            }
        } catch (error: android.content.ActivityNotFoundException) {
            result.error("APP_UNAVAILABLE", "No app can share images.", null)
        } catch (error: Exception) {
            result.error("UNAVAILABLE", "The QR image could not be saved or shared.", null)
        }
    }

    private fun save(bytes: ByteArray, name: String): Boolean {
        if (Build.VERSION.SDK_INT < 29) throw UnsupportedOperationException("Android 10 or newer is required")
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, "$name-${System.currentTimeMillis()}.png")
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Kesor Bank")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return false
        try {
            resolver.openOutputStream(uri).use { out -> out!!.write(bytes) }
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return true
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    private fun share(bytes: ByteArray, name: String, text: String?) {
        val dir = File(context.cacheDir, "shared-images").apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        val file = File(dir, "$name.png").apply { writeBytes(bytes) }
        val uri = FileProvider.getUriForFile(context, context.packageName + ".share", file)
        val send = Intent(Intent.ACTION_SEND)
            .setType("image/png")
            .putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        if (!text.isNullOrBlank()) send.putExtra(Intent.EXTRA_TEXT, text.take(200))
        val chooser = Intent.createChooser(send, "Share QR code")
        val host = activity
        if (host != null) host.startActivity(chooser)
        else context.startActivity(chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
