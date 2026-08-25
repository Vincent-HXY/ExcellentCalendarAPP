package com.excellentcalendar.excellent_calendar.android.alarm

import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderContract

interface ReminderScheduler {
    fun schedule(reminder: ReminderContract): ScheduleResult

    fun cancel(reminderId: String): CancelResult

    fun canScheduleExactAlarms(): Boolean = true
}

sealed class ScheduleResult {
    data object Success : ScheduleResult()

    /** Popup dispatcher was registered with an Android-permitted inexact API. */
    data object ApproximateSuccess : ScheduleResult()

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
