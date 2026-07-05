package com.excellentcalendar.excellent_calendar.android.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.SchedulePendingRemindersContract
import com.excellentcalendar.excellent_calendar.bridge.native.AndroidNativeBridgeFactory
import com.excellentcalendar.excellent_calendar.bridge.reminder.PendingReminderScheduleService
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.concurrent.Executors

class BootReminderRescheduler(
    private val pendingService: PendingReminderScheduleService,
    private val now: () -> Instant = { Instant.now() },
) {
    fun scheduleSevenDayWindow(): NativeResultContract {
        val from = now()
        return pendingService.schedulePending(
            SchedulePendingRemindersContract.bootWindow(
                fromAt = from.toString(),
                toAt = from.plus(HorizonMinutes, ChronoUnit.MINUTES).toString(),
                limit = BatchLimit,
            ),
        )
    }

    companion object {
        const val HorizonMinutes = 10080L
        const val BatchLimit = 128
    }
}

class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in SupportedActions) return
        val pendingResult = goAsync()
        Executor.execute {
            try {
                val nativeBridge = AndroidNativeBridgeFactory.create(context)
                val scheduler = AlarmManagerReminderScheduler(context)
                val service = PendingReminderScheduleService(
                    nativeBridge = nativeBridge,
                    scheduler = scheduler,
                    logger = { operation, reminderId, message ->
                        Log.d(LogTag, "operation=$operation reminder_id=${reminderId ?: "null"} $message")
                    },
                )
                val result = BootReminderRescheduler(service).scheduleSevenDayWindow()
                Log.d(LogTag, "boot reschedule completed ok=${result.ok} request_id=${result.requestId}")
            } catch (error: Throwable) {
                Log.e(LogTag, "boot reschedule failed type=${error.javaClass.simpleName}")
            } finally {
                pendingResult.finish()
            }
        }
    }

    companion object {
        private const val LogTag = "ExcellentCalendarBoot"
        private val Executor = Executors.newSingleThreadExecutor()
        private val SupportedActions = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
        )
    }
}
