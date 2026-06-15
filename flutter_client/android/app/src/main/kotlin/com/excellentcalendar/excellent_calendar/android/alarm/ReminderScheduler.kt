package com.excellentcalendar.excellent_calendar.android.alarm

import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderContract

interface ReminderScheduler {
    fun schedule(reminder: ReminderContract): ScheduleResult

    fun cancel(reminderId: String): CancelResult
}

sealed class ScheduleResult {
    data object Success : ScheduleResult()

    data class Failure(
        val code: String,
        val message: String,
        val retryable: Boolean,
    ) : ScheduleResult()
}

sealed class CancelResult {
    data object Success : CancelResult()

    data class Failure(
        val code: String,
        val message: String,
        val retryable: Boolean,
    ) : CancelResult()
}
