package com.bank.customer_app

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

/** Development transport only. Never log intent data or private channel arguments. */
class MerchantLinkBridge(private val context: Context) : MethodChannel.MethodCallHandler {
    private val customer = context.packageName == "com.bank.customer_app"
    private val target = if (customer) "com.bank.merchant_app" else "com.bank.customer_app"
    private val incoming = if (customer) "kesorbank://merchant/approve" else "kesormerchant://auth/callback"
    private val outgoing = if (customer) "kesormerchant://auth/callback" else "kesorbank://merchant/approve"
    // Owner transfers (M8): their own exact links and slot, so sign-in links are never confused with them.
    private val incomingTransfer = if (customer) "kesorbank://merchant/transfer" else "kesormerchant://transfer/callback"
    private val outgoingTransfer = if (customer) "kesormerchant://transfer/callback" else "kesorbank://merchant/transfer"
    private var pending: String? = null
    private var pendingTransfer: String? = null
    private val debugCertificate = "ae861749ac17ba744e16064146dc0320e27bdde8b5f61b55939c90baf1cbc2b4"

    private fun development() = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    private fun exact(uri: Uri, base: String): Boolean =
        uri.toString().length <= 2048 && uri.isHierarchical && uri.fragment == null &&
        uri.encodedAuthority == Uri.parse(base).encodedAuthority &&
        uri.scheme == Uri.parse(base).scheme && uri.encodedPath == Uri.parse(base).encodedPath

    fun handleIntent(intent: Intent?) {
        if (!development() || intent?.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        val value = uri.toString()
        // Do not replace a request awaiting Dart. Server + Dart enforce authorization.
        when {
            exact(uri, incoming) -> if (pending == null) pending = value
            exact(uri, incomingTransfer) -> if (pendingTransfer == null) pendingTransfer = value
        }
    }

    @Suppress("DEPRECATION")
    private fun verifyTarget() {
        check(development())
        val pm = context.packageManager
        val info = pm.getPackageInfo(target, if (Build.VERSION.SDK_INT >= 28)
            PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES)
        val signers = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        check(signers != null && signers.size == 1)
        val digest = MessageDigest.getInstance("SHA-256").digest(signers[0].toByteArray())
            .joinToString("") { "%02x".format(it.toInt() and 255) }
        check(digest == debugCertificate)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "take" -> {
                    val value = pending
                    pending = null
                    result.success(value)
                }
                "takeTransfer" -> {
                    val value = pendingTransfer
                    pendingTransfer = null
                    result.success(value)
                }
                "verify" -> { verifyTarget(); result.success(null) }
                "openTransfer" -> {
                    val value = call.argument<String>("uri") ?: error("Invalid link")
                    check(exact(Uri.parse(value), outgoingTransfer))
                    verifyTarget()
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(value))
                        .setClassName(target, "$target.MainActivity")
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP))
                    result.success(null)
                }
                "open" -> {
                    val value = call.argument<String>("uri") ?: error("Invalid link")
                    check(exact(Uri.parse(value), outgoing))
                    verifyTarget()
                    // Component targeting avoids resolver/chooser interception after certificate check.
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(value))
                        .setClassName(target, "$target.MainActivity")
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (_: PackageManager.NameNotFoundException) {
            result.error("PEER_MISSING", "Install the other Kesor app to continue.", null)
        } catch (_: Exception) {
            result.error("HANDOFF_UNAVAILABLE", "The Kesor app could not be verified or opened.", null)
        }
    }
}
