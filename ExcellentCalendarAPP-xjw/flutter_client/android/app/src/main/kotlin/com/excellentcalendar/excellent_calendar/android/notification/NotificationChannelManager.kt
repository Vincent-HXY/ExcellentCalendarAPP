package com.excellentcalendar.excellent_calendar.android.notification

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build

data class NotificationChannelInitialization(
    val ready: Boolean,
    val defaultChannelId: String,
)

fun interface NotificationChannelManager {
    fun ensureChannels(): NotificationChannelInitialization
}

class AndroidNotificationChannelManager(context: Context) : NotificationChannelManager {
    private val notificationManager = context.applicationContext.getSystemService(NotificationManager::class.java)

    override fun ensureChannels(): NotificationChannelInitialization {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val popup = NotificationChannel(
                PopupChannelId,
                "Calendar reminders",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                enableVibration(true)
                setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION), null)
            }
            val ring = NotificationChannel(
                RingChannelId,
                "Urgent calendar reminders",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                enableVibration(true)
                val attributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .build()
                setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM), attributes)
            }
            notificationManager.createNotificationChannels(listOf(popup, ring))
        }
        return NotificationChannelInitialization(ready = true, defaultChannelId = PopupChannelId)
    }

    companion object {
        const val PopupChannelId = "excellent_calendar_reminder_popup"
        const val RingChannelId = "excellent_calendar_reminder_ring"
    }
}
