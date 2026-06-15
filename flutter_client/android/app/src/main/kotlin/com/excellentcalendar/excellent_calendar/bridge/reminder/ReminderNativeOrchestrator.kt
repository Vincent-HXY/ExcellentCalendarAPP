package com.excellentcalendar.excellent_calendar.bridge.reminder

import com.excellentcalendar.excellent_calendar.android.alarm.CancelResult
import com.excellentcalendar.excellent_calendar.android.alarm.ReminderScheduler
import com.excellentcalendar.excellent_calendar.android.alarm.ScheduleResult
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeContractViolation
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderListResponseContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderResponseContract
import com.excellentcalendar.excellent_calendar.bridge.native.NativeEventBridge

class ReminderNativeOrchestrator(
    private val nativeBridge: NativeEventBridge,
    private val scheduler: ReminderScheduler,
    private val logger: ReminderOrchestrationLogger,
) {
    fun createReminder(requestJson: String): NativeResultContract {
        val created = parseReminderResult(nativeBridge.createReminder(requestJson))
        if (!created.ok) {
            return created
        }

        val reminder = ReminderContract.fromData(created.data)
        return when (val scheduleResult = scheduler.schedule(reminder)) {
            ScheduleResult.Success -> parseReminderResult(nativeBridge.markReminderScheduled(reminder.id))
            is ScheduleResult.Failure -> {
                logger.log(
                    operation = "reminder.create",
                    reminderId = reminder.id,
                    message = "schedule failed code=${scheduleResult.code}",
                )
                markReminderFailedOrSchedulerFailure(reminder.id, scheduleResult)
            }
        }
    }

    fun cancelReminder(requestJson: String, reminderId: String): NativeResultContract {
        val preflight = findReminder(reminderId)
        if (preflight.failure != null) {
            return preflight.failure
        }
        val reminder = preflight.reminder ?: return NativeResultContract.failure(
            code = NativeErrorCodes.ReminderNotFound,
            message = "Reminder not found",
            details = linkedMapOf("reminder_id" to reminderId),
        )

        return when (val cancelResult = scheduler.cancel(reminderId)) {
            CancelResult.Success -> {
                val cancelled = parseReminderResult(nativeBridge.cancelReminder(requestJson))
                if (!cancelled.ok) {
                    compensateAfterCancelPersistenceFailure(reminder)
                }
                cancelled
            }
            is CancelResult.Failure -> NativeResultContract.failure(
                code = cancelResult.code,
                message = cancelResult.message,
                details = linkedMapOf("reminder_id" to reminderId),
                retryable = cancelResult.retryable,
            )
        }
    }

    private fun findReminder(reminderId: String): ReminderPreflight {
        val listRequestJson = NativeContractJsonCodec.encodeObject(
            linkedMapOf(
                "include_deleted" to true,
                "pagination" to linkedMapOf(
                    "page" to 1,
                    "page_size" to PreflightPageSize,
                    "cursor" to null,
                    "sort_by" to null,
                    "sort_direction" to "asc",
                ),
                "sort_by" to "updated_at",
                "sort_direction" to "asc",
            ),
        )
        val listResult = NativeResultContract.fromJson(nativeBridge.listReminders(listRequestJson), ReminderListResponseContract::validate)
        if (!listResult.ok) {
            return ReminderPreflight(reminder = null, failure = listResult)
        }
        return ReminderPreflight(
            reminder = ReminderListResponseContract.findReminder(listResult.data, reminderId),
            failure = null,
        )
    }

    private fun markReminderFailedOrSchedulerFailure(
        reminderId: String,
        scheduleResult: ScheduleResult.Failure,
    ): NativeResultContract {
        return try {
            parseReminderResult(
                nativeBridge.markReminderFailed(
                    reminderId,
                    scheduleResult.message,
                ),
            )
        } catch (error: Throwable) {
            NativeResultContract.failure(
                code = scheduleResult.code,
                message = scheduleResult.message,
                details = linkedMapOf(
                    "reminder_id" to reminderId,
                    "mark_failed_error" to (error.message ?: error.javaClass.simpleName),
                ),
                retryable = scheduleResult.retryable,
            )
        }
    }

    private fun compensateAfterCancelPersistenceFailure(reminder: ReminderContract) {
        if (!reminder.isEnabled || reminder.status == "cancelled" || reminder.status == "sent") {
            logger.log(
                operation = "reminder.cancel",
                reminderId = reminder.id,
                message = "skip compensation status=${reminder.status} is_enabled=${reminder.isEnabled}",
            )
            return
        }
        when (val result = scheduler.schedule(reminder)) {
            ScheduleResult.Success -> logger.log(
                operation = "reminder.cancel",
                reminderId = reminder.id,
                message = "compensation reschedule succeeded",
            )
            is ScheduleResult.Failure -> logger.log(
                operation = "reminder.cancel",
                reminderId = reminder.id,
                message = "compensation reschedule failed code=${result.code}",
            )
        }
    }

    private fun parseReminderResult(json: String): NativeResultContract {
        return NativeResultContract.fromJson(json, ReminderResponseContract::validate)
    }

    companion object {
        private const val PreflightPageSize = 200
    }
}

private data class ReminderPreflight(
    val reminder: ReminderContract?,
    val failure: NativeResultContract?,
)

fun interface ReminderOrchestrationLogger {
    fun log(operation: String, reminderId: String?, message: String)
}
