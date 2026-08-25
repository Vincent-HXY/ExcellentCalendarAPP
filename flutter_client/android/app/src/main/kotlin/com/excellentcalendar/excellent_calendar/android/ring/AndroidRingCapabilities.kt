package com.excellentcalendar.excellent_calendar.android.ring

import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.RingtoneManager
import android.os.Build
import android.os.Vibrator
import android.os.VibratorManager
import com.excellentcalendar.excellent_calendar.android.notification.AndroidNotificationChannelManager

fun interface RingCapabilityProvider {
    fun snapshot(settings: RingSettingsRecord): Map<String, Any?>
}

class AndroidRingCapabilityProvider(context: Context) : RingCapabilityProvider {
    private val appContext = context.applicationContext
    private val notifications = appContext.getSystemService(NotificationManager::class.java)
    private val alarms = appContext.getSystemService(AlarmManager::class.java)
    private val audio = appContext.getSystemService(AudioManager::class.java)

    override fun snapshot(settings: RingSettingsRecord): Map<String, Any?> {
        val sdk = Build.VERSION.SDK_INT
        val runtimeNotificationGranted = sdk < 33 ||
            appContext.checkSelfPermission("android.permission.POST_NOTIFICATIONS") == PackageManager.PERMISSION_GRANTED
        val notificationPermission = if (sdk < 33) "not_required" else if (runtimeNotificationGranted) "granted" else "denied"
        val canPost = runtimeNotificationGranted && (sdk < 24 || notifications.areNotificationsEnabled())
        val canSchedule = if (Build.VERSION.SDK_INT >= 31) alarms.canScheduleExactAlarms() else true
        val exactPermission = if (sdk < 31) "not_required" else if (canSchedule) "granted" else "denied"
        val canFullScreen = if (Build.VERSION.SDK_INT >= 34) notifications.canUseFullScreenIntent() else true
        val fullScreenPermission = if (sdk < 34) "not_required" else if (canFullScreen) "granted" else "denied"
        val ringChannelEnabled = if (Build.VERSION.SDK_INT >= 26) {
            notifications.getNotificationChannel(AndroidNotificationChannelManager.RingControlChannelId)?.importance !=
                NotificationManager.IMPORTANCE_NONE
        } else {
            true
        }
        val hasAudio = sdk < 23 || audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).isNotEmpty()
        val hasVibrator = vibrator()?.hasVibrator() == true
        val selectedAvailable = settings.ringtoneUri == null || runCatching {
            appContext.contentResolver.openAssetFileDescriptor(android.net.Uri.parse(settings.ringtoneUri), "r")
                ?.use { true } ?: false
        }.getOrDefault(false)
        val blocking = buildList {
            if (!canPost) add("notification_permission_unavailable")
            if (!canSchedule) add("exact_alarm_permission_unavailable")
            if (!ringChannelEnabled) add("ring_channel_unavailable")
            if (!hasAudio && !hasVibrator) add("no_output_available")
        }
        val degradation = buildList {
            if (!canFullScreen) add("full_screen_intent_unavailable")
            if (!selectedAvailable) add("selected_ringtone_unavailable")
            if (!hasAudio) add("audio_output_unavailable")
            if (!hasVibrator) add("vibration_unavailable")
        }
        return linkedMapOf(
            "evaluated_at" to ringUtcNow(),
            "sdk_int" to sdk,
            "notification_permission" to notificationPermission,
            "exact_alarm_permission" to exactPermission,
            "full_screen_intent_permission" to fullScreenPermission,
            "can_post_notifications" to canPost,
            "can_schedule_exact_alarms" to canSchedule,
            "can_use_full_screen_intent" to canFullScreen,
            "ring_channel_enabled" to ringChannelEnabled,
            "has_audio_output" to hasAudio,
            "has_vibrator" to hasVibrator,
            "can_enable_ring" to blocking.isEmpty(),
            "blocking_reasons" to blocking,
            "degradation_reasons" to degradation,
        )
    }

    private fun vibrator(): Vibrator? = if (Build.VERSION.SDK_INT >= 31) {
        appContext.getSystemService(VibratorManager::class.java)?.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        appContext.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    }

}

fun defaultAlarmUri(context: Context): android.net.Uri? =
    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        ?: RingtoneManager.getActualDefaultRingtoneUri(context, RingtoneManager.TYPE_ALARM)
