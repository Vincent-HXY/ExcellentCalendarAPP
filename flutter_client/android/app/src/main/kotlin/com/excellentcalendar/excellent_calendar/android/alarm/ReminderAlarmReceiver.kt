package com.excellentcalendar.excellent_calendar.android.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.excellentcalendar.excellent_calendar.bridge.contract.ReconcileReminderScheduleContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderScheduleTrigger
import java.util.concurrent.Executors

class ReminderAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val isDispatcher = intent.action == ReminderDispatchAlarmScheduler.ActionDispatchAlarm
        val isLegacy = intent.action == AlarmManagerReminderScheduler.ActionReminderAlarm
        if (!isDispatcher && !isLegacy) return

        // A queued legacy broadcast must never deliver directly after migration.
        val pendingResult = goAsync()
        Executor.execute {
            try {
                ReminderWorkScheduler.ensurePeriodic(context)
                val result = ReminderCoordinatorFactory.create(context).reconcile(
                    ReconcileReminderScheduleContract(ReminderScheduleTrigger.AlarmFired, force = true),
                )
                Log.d(
                    LogTag,
                    "dispatcher handled legacy=$isLegacy planned_at=" +
                        "${intent.getStringExtra(ReminderDispatchAlarmScheduler.ExtraPlannedAt)} ok=${result.ok}",
                )
                if (!result.ok && result.error?.retryable == true) {
                    ReminderWorkScheduler.enqueueContinuation(context)
                }
            } catch (error: Throwable) {
                Log.e(LogTag, "dispatcher failed type=${error.javaClass.simpleName}")
                ReminderWorkScheduler.enqueueContinuation(context)
            } finally {
                pendingResult.finish()
            }
        }
    }

    companion object {
        private const val LogTag = "ExcellentCalendarAlarm"
        private val Executor = Executors.newSingleThreadExecutor()
    }
}
