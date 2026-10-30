package com.bank.customer_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Device settings and private, opt-in local alerts. No account values cross this channel. */
class SettingsBridge(private val context: Context) : MethodChannel.MethodCallHandler {
    private val notifications get() = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private val channelId = "kesor_activity"
    private fun allowed(): Boolean {
        if (Build.VERSION.SDK_INT >= 24 && !notifications.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= 26 && notifications.getNotificationChannel(channelId)?.importance == NotificationManager.IMPORTANCE_NONE) return false
        return true
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "notificationsEnabled" -> result.success(allowed())
                "openNotifications" -> {
                    val intent = if (Build.VERSION.SDK_INT >= 26) Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                        else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + context.packageName))
                    context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }
                "emailSupport" -> {
                    context.startActivity(Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:reachsteav2@gmail.com"))
                        .putExtra(Intent.EXTRA_SUBJECT, "Kesor Bank support").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }
                "activityAlert" -> {
                    if (!allowed()) { result.success(false); return }
                    if (Build.VERSION.SDK_INT >= 26) notifications.createNotificationChannel(
                        NotificationChannel(channelId, "Account activity", NotificationManager.IMPORTANCE_DEFAULT))
                    val builder = if (Build.VERSION.SDK_INT >= 26) android.app.Notification.Builder(context, channelId)
                                  else android.app.Notification.Builder(context)
                    val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
                    val pending = android.app.PendingIntent.getActivity(context, 0, launch,
                        android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE)
                    notifications.notify(320308, builder.setSmallIcon(android.R.drawable.ic_dialog_info)
                        .setContentTitle("Kesor Bank").setContentText("Your account activity has been updated. Open Kesor Bank to view it.")
                        .setVisibility(android.app.Notification.VISIBILITY_PRIVATE).setAutoCancel(true)
                        .setContentIntent(pending).build())
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (error: android.content.ActivityNotFoundException) {
            result.error("APP_UNAVAILABLE", "No compatible app is installed.", null)
        } catch (error: SecurityException) {
            result.error("PERMISSION_REQUIRED", "Allow notifications in Android settings.", null)
        }
    }
}
