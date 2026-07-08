package com.excellentcalendar.excellent_calendar.android.alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import java.time.Instant

interface DispatchAlarmScheduler {
    fun schedule(plannedAt: String): ScheduleResult
    fun cancel(): CancelResult
    fun canScheduleExactAlarms(): Boolean
}

/** Registers exactly one process-independent alarm for the head of the durable Reminder queue. */
class ReminderDispatchAlarmScheduler(context: Context) : DispatchAlarmScheduler {
    private val appContext = context.applicationContext
    private val alarmManager = appContext.getSystemService(AlarmManager::class.java)

    override fun schedule(plannedAt: String): ScheduleResult {
        if (!canScheduleExactAlarms()) {
            return ScheduleResult.Failure(
                NativeErrorCodes.ExactAlarmPermissionDenied,
                "Android exact alarm permission is denied.",
                retryable = true,
            )
        }
        val triggerAt = try {
            Instant.parse(plannedAt).toEpochMilli()
        } catch (_: Exception) {
            return ScheduleResult.Failure(
                NativeErrorCodes.AlarmScheduleFailed,
                "Dispatcher planned_at is not a valid UTC instant.",
                retryable = false,
            )
        }
        return try {
            val operation = dispatchPendingIntent(plannedAt, PendingIntent.FLAG_UPDATE_CURRENT)!!
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, operation)
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAt, operation)
            }
            ScheduleResult.Success
        } catch (_: SecurityException) {
            ScheduleResult.Failure(
                NativeErrorCodes.ExactAlarmPermissionDenied,
                "Android exact alarm permission is denied.",
                retryable = true,
            )
        } catch (_: RuntimeException) {
            ScheduleResult.Failure(
                NativeErrorCodes.AlarmScheduleFailed,
                "Android dispatcher alarm scheduling failed.",
                retryable = true,
            )
        }
    }

    override fun cancel(): CancelResult = try {
        val existing = dispatchPendingIntent(null, PendingIntent.FLAG_NO_CREATE)
        if (existing != null) {
            alarmManager.cancel(existing)
            existing.cancel()
        }
        CancelResult.Success
    } catch (_: RuntimeException) {
        CancelResult.Failure(
            NativeErrorCodes.AlarmCancelFailed,
            "Android dispatcher alarm cancellation failed.",
            retryable = true,
        )
    }

    override fun canScheduleExactAlarms(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()

    private fun dispatchPendingIntent(plannedAt: String?, flag: Int): PendingIntent? {
        val intent = Intent(appContext, ReminderAlarmReceiver::class.java)
            .setAction(ActionDispatchAlarm)
            .setPackage(appContext.packageName)
            .setData(Uri.parse(DispatchUri))
            .apply { if (plannedAt != null) putExtra(ExtraPlannedAt, plannedAt) }
        return PendingIntent.getBroadcast(
            appContext,
            DispatchRequestCode,
            intent,
            flag or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    companion object {
        const val ActionDispatchAlarm = "excellent_calendar.action.REMINDER_DISPATCH_ALARM"
        const val ExtraPlannedAt = "planned_at"
        private const val DispatchUri = "excellentcalendar://reminder-dispatch"
        private const val DispatchRequestCode = 9417
    }
}
