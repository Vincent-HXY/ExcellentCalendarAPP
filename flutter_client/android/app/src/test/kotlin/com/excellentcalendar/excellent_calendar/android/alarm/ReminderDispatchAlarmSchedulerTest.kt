package com.excellentcalendar.excellent_calendar.android.alarm

import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class ReminderDispatchAlarmSchedulerTest {
    @Test
    fun exactPermissionRaceFallsBackAndReportsActualApproximateMode() {
        val backend = RecordingBackend(canScheduleExact = true, exactFailure = SecurityException("revoked"))
        val scheduler = ReminderDispatchAlarmScheduler(backend)

        val result = scheduler.schedule("2026-08-25T01:02:03Z", allowApproximate = true)

        assertSame(ScheduleResult.ApproximateSuccess, result)
        assertEquals(1, backend.exactCalls)
        assertEquals(1, backend.approximateCalls)
    }

    @Test
    fun exactPermissionRaceDoesNotSilentlyDegradeWhenFallbackIsForbidden() {
        val backend = RecordingBackend(canScheduleExact = true, exactFailure = SecurityException("revoked"))
        val scheduler = ReminderDispatchAlarmScheduler(backend)

        val result = scheduler.schedule("2026-08-25T01:02:03Z", allowApproximate = false)

        val failure = result as ScheduleResult.Failure
        assertEquals(NativeErrorCodes.ExactAlarmPermissionDenied, failure.code)
        assertEquals(1, backend.exactCalls)
        assertEquals(0, backend.approximateCalls)
    }

    private class RecordingBackend(
        private val canScheduleExact: Boolean,
        private val exactFailure: RuntimeException? = null,
    ) : DispatchAlarmBackend {
        var exactCalls = 0
        var approximateCalls = 0

        override fun canScheduleExactAlarms(): Boolean = canScheduleExact

        override fun scheduleExact(triggerAt: Long, plannedAt: String) {
            exactCalls += 1
            exactFailure?.let { throw it }
        }

        override fun scheduleApproximate(triggerAt: Long, plannedAt: String) {
            approximateCalls += 1
        }

        override fun cancel() = Unit
    }
}
