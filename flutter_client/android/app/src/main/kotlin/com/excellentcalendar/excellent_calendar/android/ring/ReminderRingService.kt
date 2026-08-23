package com.excellentcalendar.excellent_calendar.android.ring

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class ReminderRingService : Service() {
    private lateinit var runtime: RingRuntime
    private val nativeAndOutputExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    override fun onCreate() {
        super.onCreate()
        runtime = RingRuntimeProvider.get(applicationContext)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action != ActionStart) return START_NOT_STICKY
        val notification = runtime.buildControlNotification()
        if (notification == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(
                    RingControlNotificationFactory.NotificationId,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                )
            } else {
                startForeground(RingControlNotificationFactory.NotificationId, notification)
            }
        } catch (_: RuntimeException) {
            nativeAndOutputExecutor.execute {
                runtime.onControlNotificationFailed()
                stopSelf()
            }
            return START_NOT_STICKY
        }
        nativeAndOutputExecutor.execute { runtime.onForegroundShown(this) }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        nativeAndOutputExecutor.shutdownNow()
        runtime.onServiceDestroyed(this)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    fun detachQuietNotification() {
        stopForeground(STOP_FOREGROUND_DETACH)
        stopSelf()
    }

    fun stopRingService(removeNotification: Boolean) {
        stopForeground(if (removeNotification) STOP_FOREGROUND_REMOVE else STOP_FOREGROUND_DETACH)
        stopSelf()
    }

    companion object {
        const val ActionStart = "excellent_calendar.action.START_RING_SERVICE"
    }
}
