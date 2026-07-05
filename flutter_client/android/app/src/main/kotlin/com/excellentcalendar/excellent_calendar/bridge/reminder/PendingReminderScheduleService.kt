package com.excellentcalendar.excellent_calendar.bridge.reminder

import com.excellentcalendar.excellent_calendar.android.alarm.ReminderScheduler
import com.excellentcalendar.excellent_calendar.android.alarm.ScheduleResult
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderResponseContract
import com.excellentcalendar.excellent_calendar.bridge.contract.SchedulePendingRemindersContract
import com.excellentcalendar.excellent_calendar.bridge.contract.SchedulableReminderBatch
import com.excellentcalendar.excellent_calendar.bridge.native.NativeEventBridge
import java.time.Instant

class PendingReminderScheduleService(
    private val nativeBridge: NativeEventBridge,
    private val scheduler: ReminderScheduler,
    private val logger: ReminderOrchestrationLogger,
    private val nowUtc: () -> String = { Instant.now().toString() },
) {
    fun schedulePending(request: SchedulePendingRemindersContract): NativeResultContract {
        val listRequest = linkedMapOf<String, Any?>(
            "from_at" to request.fromAt,
            "to_at" to request.toAt,
            "limit" to request.limit,
            "include_failed" to true,
            "include_scheduled" to request.forceReschedule,
            "supported_methods" to listOf("popup"),
        )
        val listed = NativeResultContract.fromJson(
            nativeBridge.listSchedulableReminders(NativeContractJsonCodec.encodeObject(listRequest)),
        ) { SchedulableReminderBatch.fromData(it) }
        if (!listed.ok) return listed

        val batch = SchedulableReminderBatch.fromData(listed.data)
        if (!scheduler.canScheduleExactAlarms()) {
            batch.reminders.forEach {
                markFailed(it.id, "EXACT_ALARM_PERMISSION_DENIED: Android exact alarm permission is denied.")
            }
            return NativeResultContract.failure(
                code = NativeErrorCodes.ExactAlarmPermissionDenied,
                message = "Android exact alarm permission is denied.",
                details = linkedMapOf(
                    "settings_target" to "exact_alarm",
                    "failed_reminder_ids" to batch.reminders.map { it.id },
                ),
                retryable = true,
            )
        }
        var scheduledCount = 0
        var failedCount = 0
        var skippedCount = batch.unsupportedReminderIds.size
        val failedIds = linkedSetOf<String>()
        val unsupportedIds = LinkedHashSet(batch.unsupportedReminderIds)

        for (reminder in batch.reminders) {
            if (!reminder.isEnabled || reminder.deletedAt != null || "popup" !in reminder.methods) {
                skippedCount += 1
                unsupportedIds.add(reminder.id)
                continue
            }
            when (val scheduled = scheduler.schedule(reminder)) {
                ScheduleResult.Success -> {
                    val marked = markScheduled(reminder.id)
                    if (marked.ok) {
                        scheduledCount += 1
                    } else {
                        scheduler.cancel(reminder.id)
                        failedCount += 1
                        failedIds.add(reminder.id)
                        logger.log("reminder.schedule_pending", reminder.id, "mark_scheduled failed; alarm cancelled")
                    }
                }
                is ScheduleResult.Failure -> {
                    failedCount += 1
                    failedIds.add(reminder.id)
                    markFailed(reminder.id, scheduled.message)
                    logger.log(
                        "reminder.schedule_pending",
                        reminder.id,
                        "alarm registration failed code=${scheduled.code}",
                    )
                }
            }
        }

        return NativeResultContract.success(
            linkedMapOf(
                "scheduled_count" to scheduledCount,
                "skipped_count" to skippedCount,
                "failed_count" to failedCount,
                "unsupported_method_count" to unsupportedIds.size,
                "has_more" to batch.hasMore,
                "failed_reminder_ids" to failedIds.toList(),
                "unsupported_reminder_ids" to unsupportedIds.toList(),
            ),
        )
    }

    private fun markScheduled(reminderId: String): NativeResultContract {
        val request = NativeContractJsonCodec.encodeObject(
            linkedMapOf("id" to reminderId, "scheduled_at" to nowUtc()),
        )
        return NativeResultContract.fromJson(
            nativeBridge.markReminderScheduled(request),
            ReminderResponseContract::validate,
        )
    }

    private fun markFailed(reminderId: String, reason: String) {
        try {
            val request = NativeContractJsonCodec.encodeObject(
                linkedMapOf("id" to reminderId, "failure_reason" to reason),
            )
            NativeResultContract.fromJson(
                nativeBridge.markReminderFailed(request),
                ReminderResponseContract::validate,
            )
        } catch (error: Throwable) {
            logger.log(
                "reminder.schedule_pending",
                reminderId,
                "mark_failed failed type=${error.javaClass.simpleName}",
            )
        }
    }
}
