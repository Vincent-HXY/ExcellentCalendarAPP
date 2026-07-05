package com.excellentcalendar.excellent_calendar.android.notification

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import com.excellentcalendar.excellent_calendar.MainActivity
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes

data class ReminderNotificationContent(
    val reminderId: String,
    val targetType: String,
    val targetId: String,
    val title: String,
    val body: String?,
    val plannedAt: String,
)

sealed class NotificationPostResult {
    data class Success(val androidNotificationId: Int) : NotificationPostResult()
    data class Failure(
        val code: String,
        val message: String,
        val retryable: Boolean,
    ) : NotificationPostResult()
}

interface NotificationDisplayService {
    fun post(content: ReminderNotificationContent, sentAt: String): NotificationPostResult
    fun cancel(reminderId: String)
}

class AndroidNotificationDisplayService(
    context: Context,
    private val channelManager: NotificationChannelManager = AndroidNotificationChannelManager(context),
) : NotificationDisplayService {
    private val appContext = context.applicationContext
    private val notificationManager = appContext.getSystemService(NotificationManager::class.java)

    override fun post(content: ReminderNotificationContent, sentAt: String): NotificationPostResult {
        if (!canPostNotifications()) {
            return NotificationPostResult.Failure(
                NativeErrorCodes.NotificationPermissionDenied,
                "Android notification permission is denied.",
                retryable = true,
            )
        }
        return try {
            channelManager.ensureChannels()
            val notificationId = stableNotificationId(content.reminderId)
            notificationManager.notify(notificationId, buildNotification(content, sentAt))
            NotificationPostResult.Success(notificationId)
        } catch (error: SecurityException) {
            NotificationPostResult.Failure(
                NativeErrorCodes.NotificationPermissionDenied,
                "Android notification permission is denied.",
                retryable = true,
            )
        } catch (error: RuntimeException) {
            NotificationPostResult.Failure(
                NativeErrorCodes.NotificationDeliveryFailed,
                "Android notification delivery failed.",
                retryable = true,
            )
        }
    }

    override fun cancel(reminderId: String) {
        notificationManager.cancel(stableNotificationId(reminderId))
    }

    private fun canPostNotifications(): Boolean {
        val runtimeGranted = Build.VERSION.SDK_INT < 33 ||
            appContext.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        val enabled = Build.VERSION.SDK_INT < Build.VERSION_CODES.N || notificationManager.areNotificationsEnabled()
        return runtimeGranted && enabled
    }

    private fun buildNotification(content: ReminderNotificationContent, sentAt: String): Notification {
        val payload = linkedMapOf<String, Any?>(
            // One-time reminders use their stable reminder id as the tap-delivery deduplication id.
            "notification_id" to content.reminderId,
            "reminder_id" to content.reminderId,
            "target_type" to content.targetType,
            "target_id" to content.targetId,
            "route" to routeFor(content.targetType),
            "opened_at" to sentAt,
        )
        val tapIntent = Intent(appContext, MainActivity::class.java)
            .setAction(AndroidNotificationRuntime.ActionOpenReminder)
            .setPackage(appContext.packageName)
            .setData(Uri.parse("excellentcalendar://notification/${Uri.encode(content.reminderId)}"))
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(
                AndroidNotificationRuntime.ExtraPayloadJson,
                NativeContractJsonCodec.encodeObject(payload),
            )
        val contentIntent = PendingIntent.getActivity(
            appContext,
            0,
            tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(appContext, AndroidNotificationChannelManager.PopupChannelId)
        } else {
            Notification.Builder(appContext)
        }
        return builder
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(content.title)
            .setContentText(content.body ?: "")
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .build()
    }

    private fun routeFor(targetType: String): String? = when (targetType) {
        "event" -> "/event/detail"
        "habit" -> "/habit/detail"
        "anniversary" -> "/anniversary/detail"
        else -> null
    }

    companion object {
        fun stableNotificationId(reminderId: String): Int = reminderId.hashCode() and Int.MAX_VALUE
    }
}
