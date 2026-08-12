package com.excellentcalendar.excellent_calendar.bridge.channel

import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReconcileReminderScheduleContract
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderScheduleReconciler
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MutationScheduleHookTest {
    @Test
    fun failedReconcileQueuesRetryWithoutThrowing() {
        var retries = 0
        val logs = mutableListOf<String>()
        val hook = MutationScheduleHook(
            reminderScheduleCoordinator = reconciler {
                NativeResultContract.failure(
                    code = NativeErrorCodes.NativeInternalError,
                    message = "schedule failed",
                    requestId = "reconcile-request",
                )
            },
            reconcileRetryEnqueuer = { retries += 1 },
            logger = NativeBridgeLogger { _, _, message -> logs += message },
        )

        hook.afterMutation("event.update")

        assertEquals(1, retries)
        assertTrue(logs.single().contains("domain mutation committed; reconcile deferred"))
    }

    @Test
    fun thrownReconcileQueuesRetryWithoutEscapingPostCommitHook() {
        var retries = 0
        val hook = MutationScheduleHook(
            reminderScheduleCoordinator = reconciler { throw IllegalStateException("alarm unavailable") },
            reconcileRetryEnqueuer = { retries += 1 },
            logger = NativeBridgeLogger { _, _, _ -> },
        )

        hook.afterMutation("reminder.create")

        assertEquals(1, retries)
    }

    @Test
    fun successfulReconcileDoesNotQueueRetry() {
        var retries = 0
        val hook = MutationScheduleHook(
            reminderScheduleCoordinator = reconciler { NativeResultContract.success(mapOf("action" to "scheduled")) },
            reconcileRetryEnqueuer = { retries += 1 },
            logger = NativeBridgeLogger { _, _, _ -> },
        )

        hook.afterMutation("event.complete")

        assertEquals(0, retries)
    }

    private fun reconciler(
        block: (ReconcileReminderScheduleContract) -> NativeResultContract,
    ): ReminderScheduleReconciler = object : ReminderScheduleReconciler {
        override fun reconcile(
            request: ReconcileReminderScheduleContract,
            executionBudgetMillis: Long,
        ): NativeResultContract = block(request)
    }
}
