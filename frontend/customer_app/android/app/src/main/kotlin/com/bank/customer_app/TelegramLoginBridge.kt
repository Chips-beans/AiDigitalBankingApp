package com.bank.customer_app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/** Telegram's native /crossapp flow with backend-owned state, nonce and PKCE.
 * No client secret, provider token, or banking session is embedded in a return URL.
 * Protocol reference: TelegramMessenger/telegram-login-android (TelegramLogin.kt).
 */
class TelegramLoginBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val executor = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var expectedState: String? = null
    private var expectedRedirect: String? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "cancel" -> { cancel(); result.success(null) }
            "authorize" -> authorize(call, result)
            else -> result.notImplemented()
        }
    }

    private fun authorize(call: MethodCall, result: MethodChannel.Result) {
        if (pending != null) { result.error("TELEGRAM_UNAVAILABLE", "A login is already active.", null); return }
        val auth = call.argument<String>("authorizationUrl")?.let(Uri::parse)
        val redirect = call.argument<String>("redirectUri")
        val state = call.argument<String>("flowId")
        if (auth == null || redirect != REDIRECT || state == null || !state.matches(Regex("[A-Za-z0-9_-]{43}")) ||
            auth.scheme != "https" || auth.host != "oauth.telegram.org" || auth.port != -1 ||
            auth.userInfo != null || auth.fragment != null || auth.path != "/auth" ||
            auth.queryParameterNames.any { auth.getQueryParameters(it).size != 1 } ||
            auth.getQueryParameter("state") != state || auth.getQueryParameter("redirect_uri") != REDIRECT ||
            auth.getQueryParameter("nonce").isNullOrBlank() || auth.getQueryParameter("code_challenge").isNullOrBlank() ||
            auth.getQueryParameter("code_challenge_method") != "S256") {
            result.error("TELEGRAM_UNAVAILABLE", "Invalid native login configuration.", null); return
        }
        pending = result
        expectedState = state
        expectedRedirect = redirect
        executor.execute {
            val nativeUrl = crossAppUrl(auth)
            activity.runOnUiThread {
                if (pending !== result) return@runOnUiThread
                try {
                    if (nativeUrl != null) {
                        try { activity.startActivity(Intent(Intent.ACTION_VIEW, nativeUrl)); return@runOnUiThread }
                        catch (_: ActivityNotFoundException) { /* Use the system browser with the same bound flow. */ }
                    }
                    activity.startActivity(Intent(Intent.ACTION_VIEW, auth))
                } catch (_: Exception) {
                    finishError("TELEGRAM_UNAVAILABLE", "Telegram login could not be opened.")
                }
            }
        }
    }

    private fun crossAppUrl(auth: Uri): Uri? {
        // The fixed provider endpoint is the only network destination. Do not follow redirects.
        val url = auth.buildUpon().path("/crossapp").appendQueryParameter("android_sdk", "1").build()
        var connection: HttpURLConnection? = null
        return try {
            connection = URL(url.toString()).openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 5000
            connection.readTimeout = 5000
            connection.setRequestProperty("Accept", "application/json")
            if (connection.responseCode != 200) return null
            val body = connection.inputStream.bufferedReader().use { reader ->
                val chars = CharArray(65537)
                var count = 0
                while (count < chars.size) {
                    val read = reader.read(chars, count, chars.size - count)
                    if (read < 0) break
                    count += read
                }
                if (count > 65536) return null
                String(chars, 0, count)
            }
            val json = JSONObject(body)
            val raw = json.optString("url").ifEmpty { json.optJSONObject("result")?.optString("url") ?: "" }
            val uri = Uri.parse(raw)
            if (raw.length <= 16384 && uri.scheme == "tg" && uri.userInfo == null) uri else null
        } catch (_: Exception) { null }
        finally { connection?.disconnect() }
    }

    fun handleIntent(intent: Intent) {
        if (pending == null) return // Unsolicited links/cold starts cannot establish a session.
        val uri = intent.data ?: return
        val redirect = Uri.parse(expectedRedirect ?: return)
        if (uri.scheme != "https" || uri.host != redirect.host || uri.port != -1 || uri.userInfo != null ||
            uri.path != redirect.path || uri.fragment != null ||
            uri.queryParameterNames.any { uri.getQueryParameters(it).size != 1 } ||
            uri.getQueryParameter("state") != expectedState) return
        if (uri.getQueryParameter("error") != null) {
            finishError("TELEGRAM_CANCELLED", "Telegram approval was cancelled."); return
        }
        val code = uri.getQueryParameter("code")
        if (code.isNullOrBlank() || code.length > 4096) {
            finishError("TELEGRAM_REJECTED", "Invalid login response."); return
        }
        val result = pending
        clear()
        result?.success(uri.toString())
    }

    private fun clear() { pending = null; expectedState = null; expectedRedirect = null }
    private fun finishError(code: String, message: String) {
        val result = pending
        clear()
        result?.error(code, message, null)
    }
    fun cancel() { finishError("TELEGRAM_CANCELLED", "Telegram approval was cancelled.") }
    fun dispose() { cancel(); executor.shutdownNow() }

    companion object {
        const val REDIRECT = "https://app937652339-login.tg.dev/tglogin"
    }
}
