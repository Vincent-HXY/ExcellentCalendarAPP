package com.excellentcalendar.excellent_calendar.bridge.reminder

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReconcileReminderScheduleContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderScheduleTrigger
import com.excellentcalendar.excellent_calendar.bridge.native.NativeBridgeUnavailableException
import com.excellentcalendar.excellent_calendar.bridge.native.NativeHabitBridge
import com.excellentcalendar.excellent_calendar.bridge.runtime.DeviceTimezoneProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HabitReminderReconcilerTest {
    @Test
    fun continuesWithStrictCursorAndAggregatesSchedulingHint() {
        val bridge = ReconcileBridge(
            page(2, true, "cursor-1", schedule = true),
            page(1, false, null, schedule = false),
        )
        var continuations = 0
        val run = reconciler(bridge) { continuations++ }.reconcile(ReminderScheduleTrigger.BootCompleted)

        assertTrue(run.result.ok)
        assertTrue(run.scheduleReconciliationRequired)
        assertFalse(run.continuationRequired)
        assertEquals(0, continuations)
        assertEquals(listOf(null, "cursor-1"), bridge.cursors)
        assertEquals(listOf("device_boot", "device_boot"), bridge.triggers)
    }

    @Test
    fun rejectsZeroProgressAndRepeatedCursorWithoutLooping() {
        val zero = ReconcileBridge(page(0, true, "cursor-1"))
        val zeroRun = reconciler(zero) { _ -> }.reconcile(ReminderScheduleTrigger.TimeChanged)
        assertEquals(NativeErrorCodes.ContractValidationFailed, zeroRun.result.error?.code)
        assertEquals(1, zero.calls)

        val repeated = ReconcileBridge(page(1, true, "same"), page(1, true, "same"))
        val repeatedRun = reconciler(repeated) { _ -> }.reconcile(ReminderScheduleTrigger.TimezoneChanged)
        assertEquals(NativeErrorCodes.ContractValidationFailed, repeatedRun.result.error?.code)
        assertEquals(2, repeated.calls)
    }

    @Test
    fun twentyPageBudgetEnqueuesOneContinuation() {
        val responses = (1..20).map { page(100, true, "cursor-$it", schedule = true) }.toTypedArray()
        val bridge = ReconcileBridge(*responses)
        val continuations = mutableListOf<HabitReconcileContinuation>()
        val run = reconciler(bridge) { continuations += it }.reconcile(ReminderScheduleTrigger.DateChanged)

        assertTrue(run.result.ok)
        assertTrue(run.continuationRequired)
        assertEquals(20, bridge.calls)
        assertEquals(1, continuations.size)
        assertEquals("cursor-20", continuations.single().cursor)
        assertEquals(ReminderScheduleTrigger.DateChanged, continuations.single().trigger)
        assertEquals("Asia/Shanghai", continuations.single().timezone)
        assertEquals("date_changed", bridge.triggers.first())

        val resumedBridge = ReconcileBridge(page(1, false, null))
        val resumed = reconciler(resumedBridge) { _ -> }.reconcile(
            continuations.single().trigger,
            initialCursor = continuations.single().cursor,
        )
        assertTrue(resumed.result.ok)
        assertEquals(listOf("cursor-20"), resumedBridge.cursors)
    }

    @Test
    fun continuationEnqueueFailureIsRetryableAndNeverReportedAsSuccess() {
        val responses = (1..20).map { page(100, true, "cursor-$it") }.toTypedArray()
        val run = reconciler(ReconcileBridge(*responses)) {
            error("fixture: WorkManager rejected continuation")
        }.reconcile(ReminderScheduleTrigger.DateChanged)

        assertFalse(run.result.ok)
        assertEquals(NativeErrorCodes.NativeInternalError, run.result.error?.code)
        assertTrue(run.result.error?.retryable == true)
        assertFalse(run.continuationRequired)
    }

    @Test
    fun unavailableJniBecomesAStableNativeFailure() {
        val bridge = unavailableBridge()

        val run = reconciler(bridge) { _ -> }.reconcile(ReminderScheduleTrigger.AppStart)

        assertFalse(run.result.ok)
        assertEquals(NativeErrorCodes.NativeInternalError, run.result.error?.code)
        assertFalse(run.continuationRequired)
    }

    @Test
    fun unavailableHabitJniDoesNotStarveSharedReminderReconciliation() {
        val shared = RecordingSharedReconciler()
        val reconciler = HabitAwareReminderScheduleReconciler(
            habit = reconciler(unavailableBridge()) { _ -> },
            shared = shared,
        )
        val request = ReconcileReminderScheduleContract(ReminderScheduleTrigger.AppStart, force = true)

        val result = reconciler.reconcile(request, executionBudgetMillis = 1_000)

        assertFalse(result.ok)
        assertEquals(NativeErrorCodes.NativeInternalError, result.error?.code)
        assertEquals(1, shared.reconcileCalls)
    }

    @Test
    fun unavailableHabitJniDoesNotStarveSharedOutcomeReconciliation() {
        val shared = RecordingSharedReconciler()
        val reconciler = HabitAwareReminderScheduleReconciler(
            habit = reconciler(unavailableBridge()) { _ -> },
            shared = shared,
        )
        val request = ReconcileReminderScheduleContract(ReminderScheduleTrigger.AppStart, force = true)

        val result = reconciler.reconcileWithOutcome(request, executionBudgetMillis = 1_000)

        assertFalse(result.result.ok)
        assertEquals(NativeErrorCodes.NativeInternalError, result.result.error?.code)
        assertEquals(1, shared.outcomeCalls)
    }

    @Test
    fun habitContinuationDefersSharedReconciliationUntilTheLastPage() {
        val responses = (1..20).map { page(100, true, "cursor-$it") }.toTypedArray()
        val shared = RecordingSharedReconciler()
        val scheduleReconciler = HabitAwareReminderScheduleReconciler(
            habit = reconciler(ReconcileBridge(*responses)) { _ -> },
            shared = shared,
        )
        val request = ReconcileReminderScheduleContract(ReminderScheduleTrigger.DateChanged, force = true)

        val result = scheduleReconciler.reconcile(request, executionBudgetMillis = 1_000)
        val outcome = HabitAwareReminderScheduleReconciler(
            habit = reconciler(ReconcileBridge(*responses)) { _ -> },
            shared = shared,
        ).reconcileWithOutcome(request, executionBudgetMillis = 1_000)

        assertTrue(result.ok)
        assertTrue(outcome.result.ok)
        assertEquals(null, outcome.scheduleMode)
        assertEquals(0, shared.reconcileCalls)
        assertEquals(0, shared.outcomeCalls)
    }

    @Test
    fun dispatcherReconcilesHabitBeforeSharedDeliveryAndFailsClosed() {
        val order = mutableListOf<String>()
        val bridge = ReconcileBridge(page(1, false, null)).apply {
            onRequest = { order += "habit" }
        }
        val shared = RecordingSharedReconciler().apply {
            onDispatcher = { order += "shared" }
        }
        val reconciler = HabitAwareReminderScheduleReconciler(
            habit = reconciler(bridge) { _ -> },
            shared = shared,
        )

        val result = reconciler.reconcileDispatcherAlarm("2026-08-28T16:01:00Z")

        assertTrue(result.ok)
        assertEquals(listOf("habit", "shared"), order)
        assertEquals(1, shared.dispatcherCalls)

        val unavailableShared = RecordingSharedReconciler()
        val unavailable = HabitAwareReminderScheduleReconciler(
            habit = reconciler(unavailableBridge()) { _ -> },
            shared = unavailableShared,
        ).reconcileDispatcherAlarm("2026-08-28T16:01:00Z")
        assertFalse(unavailable.ok)
        assertEquals(0, unavailableShared.dispatcherCalls)
    }

    @Test
    fun dispatcherBudgetPersistsPlannedAtAndDefersSharedDelivery() {
        val responses = (1..20).map { page(100, true, "cursor-$it") }.toTypedArray()
        val continuations = mutableListOf<HabitReconcileContinuation>()
        val shared = RecordingSharedReconciler()
        val reconciler = HabitAwareReminderScheduleReconciler(
            habit = reconciler(ReconcileBridge(*responses)) { continuations += it },
            shared = shared,
        )

        val result = reconciler.reconcileDispatcherAlarm("2026-08-28T16:01:00Z")

        assertTrue(result.ok)
        assertEquals(0, shared.dispatcherCalls)
        assertEquals("cursor-20", continuations.single().cursor)
        assertEquals(
            "2026-08-28T16:01:00Z",
            continuations.single().dispatcherPlannedAt,
        )
    }

    private fun reconciler(
        bridge: NativeHabitBridge,
        continuation: (HabitReconcileContinuation) -> Unit,
    ) = HabitReminderReconciler(
        bridge,
        DeviceTimezoneProvider { "Asia/Shanghai" },
        continuation,
        { _, _, _ -> },
    )

    private fun unavailableBridge() = object : NativeHabitBridge {
        override fun reconcileHabitReminders(requestJson: String): String =
            throw NativeBridgeUnavailableException("fixture: missing Habit JNI symbol")
    }

    private class RecordingSharedReconciler : ReminderScheduleReconciler {
        var reconcileCalls = 0
        var outcomeCalls = 0
        var dispatcherCalls = 0
        var onDispatcher: (() -> Unit)? = null

        override fun reconcile(
            request: ReconcileReminderScheduleContract,
            executionBudgetMillis: Long,
        ): NativeResultContract {
            reconcileCalls++
            return NativeResultContract.success(emptyMap<String, Any?>(), contractVersion = 2)
        }

        override fun reconcileWithOutcome(
            request: ReconcileReminderScheduleContract,
            executionBudgetMillis: Long,
        ): ReminderScheduleReconciliation {
            outcomeCalls++
            return ReminderScheduleReconciliation(
                result = NativeResultContract.success(emptyMap<String, Any?>(), contractVersion = 2),
                scheduleMode = null,
            )
        }

        override fun reconcileDispatcherAlarm(
            plannedAt: String,
            executionBudgetMillis: Long,
        ): NativeResultContract {
            dispatcherCalls++
            onDispatcher?.invoke()
            return NativeResultContract.success(emptyMap<String, Any?>(), contractVersion = 2)
        }
    }

    private class ReconcileBridge(vararg responses: Map<String, Any?>) : NativeHabitBridge {
        private val queue = ArrayDeque(responses.toList())
        var calls = 0
        var onRequest: (() -> Unit)? = null
        val cursors = mutableListOf<String?>()
        val triggers = mutableListOf<String>()
        override fun reconcileHabitReminders(requestJson: String): String {
            calls++
            onRequest?.invoke()
            val request = NativeContractJsonCodec.decodeObject(requestJson)
            cursors += request["cursor"] as String?
            triggers += request["trigger_source"] as String
            return NativeContractJsonCodec.encodeObject(NativeResultContract.success(queue.removeFirst(), contractVersion = 2).toMap())
        }
        override fun createHabit(requestJson: String): String = error("unused")
        override fun updateHabit(requestJson: String): String = error("unused")
        override fun listHabits(requestJson: String): String = error("unused")
        override fun getHabitDetail(requestJson: String): String = error("unused")
        override fun endHabit(requestJson: String): String = error("unused")
        override fun deleteHabit(requestJson: String): String = error("unused")
        override fun checkInHabit(requestJson: String): String = error("unused")
        override fun clearHabitCheckIn(requestJson: String): String = error("unused")
        override fun listHabitDailyStatuses(requestJson: String): String = error("unused")
        override fun setHabitReminder(requestJson: String): String = error("unused")
    }

    companion object {
        private fun page(processed: Int, more: Boolean, cursor: String?, schedule: Boolean = false) = linkedMapOf<String, Any?>(
            "request_limit" to 100,
            "processed_count" to processed,
            "materialized_count" to processed,
            "expired_count" to 0,
            "cancelled_count" to 0,
            "unchanged_count" to 0,
            "schedule_reconciliation_required" to schedule,
            "has_more" to more,
            "next_cursor" to cursor,
        )
    }
}
