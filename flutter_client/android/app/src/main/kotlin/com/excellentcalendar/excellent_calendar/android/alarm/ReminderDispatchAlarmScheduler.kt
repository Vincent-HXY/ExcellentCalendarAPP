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
    fun schedule(plannedAt: String, allowApproximate: Boolean): ScheduleResult = schedule(plannedAt)
    fun cancel(): CancelResult
    fun canScheduleExactAlarms(): Boolean
}

/** Registers exactly one process-independent alarm for the head of the durable Reminder queue. */
class ReminderDispatchAlarmScheduler internal constructor(
    private val backend: DispatchAlarmBackend,
) : DispatchAlarmScheduler {
    constructor(context: Context) : this(AndroidDispatchAlarmBackend(context.applicationContext))

    override fun schedule(plannedAt: String): ScheduleResult {
        return schedule(plannedAt, allowApproximate = false)
    }

    override fun schedule(plannedAt: String, allowApproximate: Boolean): ScheduleResult {
        if (!canScheduleExactAlarms() && !allowApproximate) {
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
            if (!canScheduleExactAlarms()) {
                backend.scheduleApproximate(triggerAt, plannedAt)
                ScheduleResult.ApproximateSuccess
            } else {
                backend.scheduleExact(triggerAt, plannedAt)
                ScheduleResult.Success
            }
        } catch (_: SecurityException) {
            if (allowApproximate) {
                return try {
                    backend.scheduleApproximate(triggerAt, plannedAt)
                    ScheduleResult.ApproximateSuccess
                } catch (_: RuntimeException) {
                    ScheduleResult.Failure(
                        NativeErrorCodes.AlarmScheduleFailed,
                        "Android approximate dispatcher alarm scheduling failed.",
                        retryable = true,
                    )
                }
            }
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
        backend.cancel()
        CancelResult.Success
    } catch (_: RuntimeException) {
        CancelResult.Failure(
            NativeErrorCodes.AlarmCancelFailed,
            "Android dispatcher alarm cancellation failed.",
            retryable = true,
        )
    }

    override fun canScheduleExactAlarms(): Boolean = backend.canScheduleExactAlarms()

    companion object {
        const val ActionDispatchAlarm = "excellent_calendar.action.REMINDER_DISPATCH_ALARM"
        const val ExtraPlannedAt = "planned_at"
        internal const val DispatchUri = "excellentcalendar://reminder-dispatch"
        internal const val DispatchRequestCode = 9417
    }
}

internal interface DispatchAlarmBackend {
    fun canScheduleExactAlarms(): Boolean
    fun scheduleExact(triggerAt: Long, plannedAt: String)
    fun scheduleApproximate(triggerAt: Long, plannedAt: String)
    fun cancel()
}

private class AndroidDispatchAlarmBackend(context: Context) : DispatchAlarmBackend {
    private val appContext = context.applicationContext
    private val alarmManager = appContext.getSystemService(AlarmManager::class.java)

    override fun canScheduleExactAlarms(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()

    override fun scheduleExact(triggerAt: Long, plannedAt: String) {
        val operation = dispatchPendingIntent(plannedAt, PendingIntent.FLAG_UPDATE_CURRENT)!!
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, operation)
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAt, operation)
        }
    }

    override fun scheduleApproximate(triggerAt: Long, plannedAt: String) {
        val operation = dispatchPendingIntent(plannedAt, PendingIntent.FLAG_UPDATE_CURRENT)!!
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, operation)
        } else {
            alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAt, operation)
        }
    }

    override fun cancel() {
        val existing = dispatchPendingIntent(null, PendingIntent.FLAG_NO_CREATE)
        if (existing != null) {
            alarmManager.cancel(existing)
            existing.cancel()
        }
    }

    private fun dispatchPendingIntent(plannedAt: String?, flag: Int): PendingIntent? {
        val intent = Intent(appContext, ReminderAlarmReceiver::class.java)
            .setAction(ReminderDispatchAlarmScheduler.ActionDispatchAlarm)
            .setPackage(appContext.packageName)
            .setData(Uri.parse(ReminderDispatchAlarmScheduler.DispatchUri))
            .apply {
                if (plannedAt != null) {
                    putExtra(ReminderDispatchAlarmScheduler.ExtraPlannedAt, plannedAt)
                }
            }
        return PendingIntent.getBroadcast(
            appContext,
            ReminderDispatchAlarmScheduler.DispatchRequestCode,
            intent,
            flag or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
