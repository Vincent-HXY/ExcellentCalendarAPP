package com.excellentcalendar.excellent_calendar.android.alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderContract
import java.time.Instant

class AlarmManagerReminderScheduler(
    context: Context,
) : ReminderScheduler {
    private val appContext = context.applicationContext
    private val alarmManager = appContext.getSystemService(AlarmManager::class.java)

    override fun schedule(reminder: ReminderContract): ScheduleResult {
        if (!reminder.isEnabled || reminder.status == "cancelled" || reminder.status == "sent") {
            return ScheduleResult.Success
        }
        if (reminder.methods.none { it in SupportedMethods }) {
            return ScheduleResult.Failure(
                code = NativeErrorCodes.UnsupportedReminderMethod,
                message = "Reminder has no method supported by the Android V1 local scheduler.",
                retryable = false,
            )
        }
        if (!canScheduleExactAlarms()) {
            return ScheduleResult.Failure(
                code = NativeErrorCodes.ExactAlarmPermissionDenied,
                message = "Android exact alarm permission is denied.",
                retryable = true,
            )
        }

        val triggerAtMillis = try {
            Instant.parse(reminder.remindAt).toEpochMilli()
        } catch (error: Exception) {
            return ScheduleResult.Failure(
                code = NativeErrorCodes.AlarmScheduleFailed,
                message = "Reminder remind_at is not a valid UTC instant.",
                retryable = false,
            )
        }

        return try {
            val operation = pendingIntent(
                reminder.id,
                reminder.remindAt,
                PendingIntent.FLAG_UPDATE_CURRENT,
            )
                ?: return ScheduleResult.Failure(
                    code = NativeErrorCodes.AlarmScheduleFailed,
                    message = "Android alarm PendingIntent could not be created.",
                    retryable = true,
                )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, operation)
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAtMillis, operation)
            }
            ScheduleResult.Success
        } catch (error: SecurityException) {
            ScheduleResult.Failure(
                code = NativeErrorCodes.ExactAlarmPermissionDenied,
                message = "Android exact alarm permission is denied.",
                retryable = true,
            )
        } catch (error: RuntimeException) {
            ScheduleResult.Failure(
                code = NativeErrorCodes.AlarmScheduleFailed,
                message = "Android alarm scheduling failed.",
                retryable = true,
            )
        }
    }

    override fun cancel(reminderId: String): CancelResult {
        return try {
            val existing = pendingIntent(reminderId, null, PendingIntent.FLAG_NO_CREATE)
            if (existing != null) {
                alarmManager.cancel(existing)
                existing.cancel()
            }
            CancelResult.Success
        } catch (error: SecurityException) {
            CancelResult.Failure(
                code = NativeErrorCodes.PermissionDenied,
                message = "Android alarm cancellation permission was denied.",
                retryable = true,
            )
        } catch (error: RuntimeException) {
            CancelResult.Failure(
                code = NativeErrorCodes.AlarmCancelFailed,
                message = "Android alarm cancellation failed.",
                retryable = true,
            )
        }
    }

    override fun canScheduleExactAlarms(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()
    }

    private fun pendingIntent(reminderId: String, plannedAt: String?, lookupFlag: Int): PendingIntent? {
        val flags = lookupFlag or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(appContext, StableRequestCode, intent(reminderId, plannedAt), flags)
    }

    private fun intent(reminderId: String, plannedAt: String?): Intent {
        return Intent(appContext, ReminderAlarmReceiver::class.java)
            .setAction(ActionReminderAlarm)
            .setPackage(appContext.packageName)
            .setData(Uri.parse("excellentcalendar://reminder/${Uri.encode(reminderId)}"))
            .putExtra(ExtraReminderId, reminderId)
            .apply {
                if (plannedAt != null) putExtra(ExtraPlannedAt, plannedAt)
            }
    }

    companion object {
        const val ActionReminderAlarm = "excellent_calendar.action.REMINDER_ALARM"
        const val ExtraReminderId = "reminder_id"
        const val ExtraPlannedAt = "planned_at"
        private const val StableRequestCode = 0
        private val SupportedMethods = setOf("popup")
    }
}
