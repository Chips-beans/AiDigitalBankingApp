package com.bank.customer_app

import android.app.Activity
import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Opens the system image picker and survives Android destroying the host Activity
 * while the picker is in front ("Don't keep activities", low memory). The pending
 * Dart result lives here, in the Application, and whichever MainActivity instance
 * receives the picker result forwards it. The picked image is copied to app cache
 * and only its path crosses the channel.
 */
class ImagePickerBridge(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        const val REQUEST_CODE = 0x4b50 // "KP"
        private const val MAX_BYTES = 5L * 1024 * 1024
        private val TYPES = arrayOf("image/jpeg", "image/png")
    }

    var activity: Activity? = null
    private var pending: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "pickImage") { result.notImplemented(); return }
        val host = activity
        if (host == null) { result.error("UNAVAILABLE", "The picker is not available right now.", null); return }
        if (pending != null) { result.error("ALREADY_ACTIVE", "An image picker is already open.", null); return }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("image/*")
            .putExtra(Intent.EXTRA_MIME_TYPES, TYPES)
        try {
            pending = result
            host.startActivityForResult(intent, REQUEST_CODE)
        } catch (error: android.content.ActivityNotFoundException) {
            pending = null
            result.error("APP_UNAVAILABLE", "No image picker is installed.", null)
        }
    }

    /** Called by MainActivity (possibly a recreated instance). Returns true if handled. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pending ?: return true
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return true }
        try {
            val type = context.contentResolver.getType(uri)
            if (type !in TYPES) { result.error("UNSUPPORTED_TYPE", "Choose a JPG or PNG image.", null); return true }
            val dir = File(context.cacheDir, "picked-images").apply { mkdirs() }
            dir.listFiles()?.forEach { it.delete() }
            val target = File(dir, "picked-${System.currentTimeMillis()}." + if (type == "image/png") "png" else "jpg")
            var copied = 0L
            context.contentResolver.openInputStream(uri).use { input ->
                if (input == null) throw java.io.IOException("Unreadable")
                target.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        copied += read
                        if (copied > MAX_BYTES) break
                        output.write(buffer, 0, read)
                    }
                }
            }
            if (copied > MAX_BYTES) {
                target.delete()
                result.error("TOO_LARGE", "Choose a JPG or PNG up to 5 MB.", null)
            } else {
                result.success(target.absolutePath)
            }
        } catch (error: Exception) {
            result.error("UNREADABLE", "The image could not be opened.", null)
        }
        return true
    }
}
