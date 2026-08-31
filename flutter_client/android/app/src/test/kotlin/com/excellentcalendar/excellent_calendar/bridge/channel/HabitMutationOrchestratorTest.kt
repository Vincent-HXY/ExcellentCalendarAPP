package com.excellentcalendar.excellent_calendar.bridge.channel

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReconcileReminderScheduleContract
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderScheduleMode
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderScheduleReconciler
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderScheduleReconciliation
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HabitMutationOrchestratorTest {
    @Test
    fun disabledReminderWithoutReconciliationDoesNotAskForPermissionOrSchedule() {
        var scheduleCalls = 0
        var retries = 0
        val result = orchestrator(
            canPost = false,
            reconciler = reconciler { scheduleCalls += 1; success("scheduled", ReminderScheduleMode.Exact) },
            retry = { retries += 1 },
        ).mutate("habit.create", commit(required = false, enabled = false), HabitMutationOrchestrator.Shape.Mutation)

        assertTrue(result.ok)
        assertEquals("not_required", capability(result)["schedule_status"])
        assertEquals(0, scheduleCalls)
        assertEquals(0, retries)
    }

    @Test
    fun notificationDenialKeepsCommittedDataAndDefersScheduling() {
        var scheduleCalls = 0
        var retries = 0
        val result = orchestrator(
            canPost = false,
            reconciler = reconciler { scheduleCalls += 1; success("scheduled", ReminderScheduleMode.Exact) },
            retry = { retries += 1 },
        ).mutate("habit.set_reminder", commit(required = true, enabled = true), HabitMutationOrchestrator.Shape.Mutation)

        assertTrue(result.ok)
        assertEquals(true, data(result)["data_saved"])
        assertEquals("pending_permission", capability(result)["schedule_status"])
        assertEquals(true, reminderSettings(result)["schedule_reconciliation_required"])
        assertEquals(0, scheduleCalls)
        assertEquals(1, retries)
    }

    @Test
    fun successfulSchedulingClearsThePublicDetailReconciliationFlag() {
        val result = orchestrator(
            canPost = true,
            reconciler = reconciler { success("scheduled", ReminderScheduleMode.Exact) },
        ).mutate("habit.create", commit(required = true, enabled = true), HabitMutationOrchestrator.Shape.Mutation)

        assertTrue(result.ok)
        assertEquals("scheduled_exact", capability(result)["schedule_status"])
        assertEquals(false, capability(result)["schedule_reconciliation_required"])
        assertEquals(false, reminderSettings(result)["schedule_reconciliation_required"])
    }

    @Test
    fun actualApproximateSchedulingIsReturnedAsExplicitDegradation() {
        val result = orchestrator(
            canPost = true,
            reconciler = reconciler { success("scheduled", ReminderScheduleMode.Approximate) },
        ).mutate("habit.set_reminder", commit(required = true, enabled = true), HabitMutationOrchestrator.Shape.Mutation)

        assertEquals("scheduled_approximate", capability(result)["schedule_status"])
        assertEquals(listOf("exact_alarm_permission_unavailable"), capability(result)["degradation_reasons"])
    }

    @Test
    fun schedulerFailureKeepsCommitAndEnqueuesRetry() {
        var retries = 0
        val result = orchestrator(
            canPost = true,
            reconciler = reconciler {
                ReminderScheduleReconciliation(
                    NativeResultContract.failure(NativeErrorCodes.AlarmScheduleFailed, "fixture failure", retryable = true, contractVersion = 2),
                    null,
                )
            },
            retry = { retries += 1 },
        ).mutate("habit.update", commit(required = true, enabled = true), HabitMutationOrchestrator.Shape.Mutation)

        assertTrue(result.ok)
        assertEquals(true, data(result)["data_saved"])
        assertEquals("pending_reconciliation", capability(result)["schedule_status"])
        assertEquals(1, retries)
    }

    private fun orchestrator(
        canPost: Boolean,
        reconciler: ReminderScheduleReconciler,
        retry: () -> Unit = {},
    ) = HabitMutationOrchestrator(
        coordinator = reconciler,
        capabilityProvider = AnniversaryCapabilityProvider {
            AnniversaryCapabilitySnapshot(
                notificationPermissionStatus = if (canPost) "granted" else "denied",
                exactAlarmPermissionStatus = "granted",
                canPostNotifications = canPost,
                canScheduleExactAlarms = true,
            )
        },
        retryEnqueuer = retry,
        logger = NativeBridgeLogger { _, _, _ -> },
    )

    private fun reconciler(block: () -> ReminderScheduleReconciliation) = object : ReminderScheduleReconciler {
        override fun reconcile(request: ReconcileReminderScheduleContract, executionBudgetMillis: Long): NativeResultContract =
            block().result

        override fun reconcileWithOutcome(
            request: ReconcileReminderScheduleContract,
            executionBudgetMillis: Long,
        ): ReminderScheduleReconciliation = block()
    }

    private fun success(action: String, mode: ReminderScheduleMode) = ReminderScheduleReconciliation(
        NativeResultContract.success(mapOf("action" to action), contractVersion = 2),
        mode,
    )

    private fun commit(required: Boolean, enabled: Boolean): String {
        val detail = LinkedHashMap(fixture("detail_upcoming_empty_history.valid.json"))
        detail["reminder_settings"] = linkedMapOf<String, Any?>(
            "is_enabled" to enabled,
            "template" to if (enabled) reminderTemplate() else null,
            "active_reminder_count" to if (enabled) 1 else 0,
            "schedule_reconciliation_required" to required,
        )
        val data = linkedMapOf<String, Any?>(
            "data_saved" to true,
            "detail" to detail,
            "schedule_reconciliation_required" to required,
        )
        return NativeContractJsonCodec.encodeObject(NativeResultContract.success(data, contractVersion = 2).toMap())
    }

    private fun reminderTemplate() = linkedMapOf<String, Any?>(
        "template_key" to "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
        "habit_id" to "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        "local_time" to "09:00",
        "timezone_mode" to "follow_device",
        "method" to "popup",
        "is_enabled" to true,
        "created_at" to "2026-09-01T01:00:00Z",
        "updated_at" to "2026-09-01T01:00:00Z",
        "deleted_at" to null,
    )

    private fun fixture(name: String): Map<String, Any?> {
        val directory = fixtureDirectories.firstOrNull(File::isDirectory) ?: error("Habit fixture directory not found")
        return NativeContractJsonCodec.decodeObject(File(directory, name).readText(Charsets.UTF_8))
    }

    @Suppress("UNCHECKED_CAST")
    private fun data(result: NativeResultContract) = result.data as Map<String, Any?>

    @Suppress("UNCHECKED_CAST")
    private fun capability(result: NativeResultContract) = data(result)["capability"] as Map<String, Any?>

    @Suppress("UNCHECKED_CAST")
    private fun reminderSettings(result: NativeResultContract): Map<String, Any?> {
        val detail = data(result)["detail"] as Map<String, Any?>
        return detail["reminder_settings"] as Map<String, Any?>
    }

    companion object {
        private val fixtureDirectories = listOf(
            File("../../../contracts/fixtures/habit"),
            File("../../contracts/fixtures/habit"),
            File("../contracts/fixtures/habit"),
            File("contracts/fixtures/habit"),
        )
    }
}
