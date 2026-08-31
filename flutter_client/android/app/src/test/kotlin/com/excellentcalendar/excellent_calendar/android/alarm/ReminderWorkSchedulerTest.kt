package com.excellentcalendar.excellent_calendar.android.alarm

import androidx.work.ExistingWorkPolicy
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderScheduleTrigger
import com.excellentcalendar.excellent_calendar.bridge.reminder.HabitReconcileContinuation
import org.junit.Assert.assertEquals
import org.junit.Test

class ReminderWorkSchedulerTest {
    @Test
    fun boundedContinuationAppendsAfterTheRunningUniqueWork() {
        assertEquals(
            ExistingWorkPolicy.APPEND_OR_REPLACE,
            ReminderWorkScheduler.ContinuationAppendPolicy,
        )
    }

    @Test
    fun habitContinuationPersistsCursorTriggerTimezoneAndDispatcherIdentity() {
        val data = ReminderWorkScheduler.habitContinuationInputData(
            HabitReconcileContinuation(
                cursor = "habit-r1:aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                trigger = ReminderScheduleTrigger.AlarmFired,
                timezone = "America/New_York",
                dispatcherPlannedAt = "2026-11-01T05:30:00Z",
            ),
        )

        assertEquals(
            "habit-r1:aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            data.getString(ReminderQueueWorker.InputHabitCursor),
        )
        assertEquals(
            ReminderScheduleTrigger.AlarmFired.wireValue,
            data.getString(ReminderQueueWorker.InputTrigger),
        )
        assertEquals(
            "America/New_York",
            data.getString(ReminderQueueWorker.InputHabitTimezone),
        )
        assertEquals(
            "2026-11-01T05:30:00Z",
            data.getString(ReminderQueueWorker.InputDispatcherPlannedAt),
        )
    }
}
