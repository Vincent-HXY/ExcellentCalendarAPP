package com.excellentcalendar.excellent_calendar.android.ring

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

data class RingOutputStartResult(
    val soundStarted: Boolean,
    val vibrationStarted: Boolean,
) {
    val anyStarted: Boolean get() = soundStarted || vibrationStarted
}

interface RingOutputController {
    fun start(settings: RingSettingsRecord): RingOutputStartResult
    fun stop()
}

class AndroidRingOutputController(context: Context) : RingOutputController {
    private val appContext = context.applicationContext
    private var player: MediaPlayer? = null
    private var vibrating = false

    @Synchronized
    override fun start(settings: RingSettingsRecord): RingOutputStartResult {
        stop()
        val sound = startSound(settings)
        val vibration = startVibration()
        return RingOutputStartResult(sound, vibration)
    }

    @Synchronized
    override fun stop() {
        player?.let { current ->
            runCatching { if (current.isPlaying) current.stop() }
            runCatching { current.release() }
        }
        player = null
        if (vibrating) runCatching { vibrator()?.cancel() }
        vibrating = false
    }

    private fun startSound(settings: RingSettingsRecord): Boolean {
        val preferred = settings.ringtoneUri?.let(Uri::parse)
        val candidates = listOfNotNull(preferred, defaultAlarmUri(appContext)).distinct()
        for (uri in candidates) {
            val created = runCatching {
                MediaPlayer().apply {
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build(),
                    )
                    setDataSource(appContext, uri)
                    isLooping = true
                    prepare()
                    start()
                }
            }.getOrNull()
            if (created != null) {
                player = created
                return true
            }
        }
        return false
    }

    private fun startVibration(): Boolean {
        val vibrator = vibrator() ?: return false
        if (!vibrator.hasVibrator()) return false
        return runCatching {
            val timings = longArrayOf(0, 600, 400)
            if (Build.VERSION.SDK_INT >= 26) {
                vibrator.vibrate(VibrationEffect.createWaveform(timings, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(timings, 0)
            }
            vibrating = true
            true
        }.getOrDefault(false)
    }

    private fun vibrator(): Vibrator? = if (Build.VERSION.SDK_INT >= 31) {
        appContext.getSystemService(VibratorManager::class.java)?.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        appContext.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    }
}
