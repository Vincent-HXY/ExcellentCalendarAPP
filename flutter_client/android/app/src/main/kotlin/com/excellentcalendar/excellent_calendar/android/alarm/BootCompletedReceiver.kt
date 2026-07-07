package com.excellentcalendar.excellent_calendar.android.alarm

import android.content.BroadcastReceiver
import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.util.Log
import com.excellentcalendar.excellent_calendar.bridge.contract.ReconcileReminderScheduleContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderScheduleTrigger
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.SchedulePendingRemindersContract
import com.excellentcalendar.excellent_calendar.bridge.reminder.PendingReminderScheduleService
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.concurrent.Executors

/** Compatibility seam for the previous boot-window unit tests; production uses the queue coordinator below. */
@Deprecated("Use ReminderScheduleCoordinator")
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
        val trigger = when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED -> ReminderScheduleTrigger.BootCompleted
            Intent.ACTION_MY_PACKAGE_REPLACED -> ReminderScheduleTrigger.PackageReplaced
            Intent.ACTION_TIME_CHANGED -> ReminderScheduleTrigger.TimeChanged
            Intent.ACTION_TIMEZONE_CHANGED -> ReminderScheduleTrigger.TimezoneChanged
            AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED ->
                ReminderScheduleTrigger.ManualRetry
            else -> return
        }
        val pendingResult = goAsync()
        Executor.execute {
            try {
                ReminderWorkScheduler.ensurePeriodic(context)
                val result = ReminderCoordinatorFactory.create(context).reconcile(
                    ReconcileReminderScheduleContract(trigger, force = true),
                )
                Log.d(LogTag, "reconcile trigger_source=${trigger.wireValue} ok=${result.ok}")
            } catch (error: Throwable) {
                Log.e(LogTag, "reconcile failed type=${error.javaClass.simpleName}")
                ReminderWorkScheduler.enqueueContinuation(context)
            } finally {
                pendingResult.finish()
            }
        }
    }

    companion object {
        private const val LogTag = "ExcellentCalendarBoot"
        private val Executor = Executors.newSingleThreadExecutor()
    }
}
