package com.excellentcalendar.excellent_calendar.bridge.channel

import com.excellentcalendar.excellent_calendar.android.appearance.AppearancePreferencesStore
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.native.NativeContractProfile
import com.excellentcalendar.excellent_calendar.bridge.native.NativeHabitBridge
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HabitMethodHandlerTest {
    @Test
    fun allTenPublicMethodsUseTheFrozenHandlerChain() {
        val bridge = FakeNativeHabitBridge()
        val handler = habitHandler(bridge)
        val scenarios = linkedMapOf(
            NativeMethodChannelHandler.MethodHabitCreate to createRequest(),
            NativeMethodChannelHandler.MethodHabitUpdate to updateRequest(),
            NativeMethodChannelHandler.MethodHabitList to mapOf("timezone" to Timezone),
            NativeMethodChannelHandler.MethodHabitDetail to mapOf("id" to HabitId, "timezone" to Timezone, "history_page_size" to 30),
            NativeMethodChannelHandler.MethodHabitEnd to optimisticRequest(),
            NativeMethodChannelHandler.MethodHabitDelete to optimisticRequest(),
            NativeMethodChannelHandler.MethodHabitCheckIn to checkInRequest(),
            NativeMethodChannelHandler.MethodHabitClearCheckIn to mapOf("habit_id" to HabitId, "check_date" to Date, "timezone" to Timezone),
            NativeMethodChannelHandler.MethodHabitListDailyStatuses to mapOf("habit_id" to HabitId, "start_date" to Date, "end_date" to Date, "timezone" to Timezone),
            NativeMethodChannelHandler.MethodHabitSetReminder to mapOf("habit_id" to HabitId, "expected_updated_at" to Instant, "reminder" to disabledReminder(), "timezone" to Timezone),
        )

        scenarios.forEach { (method, arguments) ->
            val result = invoke(handler, method, arguments)
            assertTrue("$method should succeed", result.map()["ok"] == true)
        }
        assertEquals(scenarios.keys.toList(), bridge.calls)
    }

    @Test
    fun publicCheckInAddsManualSourceAndForbidsActionIdentity() {
        val bridge = FakeNativeHabitBridge()
        val result = invoke(habitHandler(bridge), NativeMethodChannelHandler.MethodHabitCheckIn, checkInRequest())
        assertTrue(result.map()["ok"] == true)
        val request = NativeContractJsonCodec.decodeObject(bridge.lastRequestJson!!)
        assertEquals("manual", request["source"])
        assertEquals(null, request["occurrence_key"])
        assertEquals(null, request["action_id"])
    }

    @Test
    fun decimalHundredthsAndUnknownFieldsAreRejectedBeforeNative() {
        val bridge = FakeNativeHabitBridge()
        val decimal = createRequest().toMutableMap().apply { this["target_count_hundredths"] = 1.25; this["unit"] = "km" }
        val result = invoke(habitHandler(bridge), NativeMethodChannelHandler.MethodHabitCreate, decimal).map()
        assertEquals(false, result["ok"])
        assertEquals(NativeErrorCodes.ContractValidationFailed, errorCode(result))
        assertTrue(bridge.calls.isEmpty())

        val extra = createRequest().toMutableMap().apply { this["habit_id"] = HabitId }
        assertEquals(false, invoke(habitHandler(bridge), NativeMethodChannelHandler.MethodHabitCreate, extra).map()["ok"])
        assertTrue(bridge.calls.isEmpty())
    }

    @Test
    fun adjacentMaximumHundredthsRemainDistinctAcrossJson() {
        val bridge = FakeNativeHabitBridge()
        listOf(9_007_199_254_740_990L, 9_007_199_254_740_991L).forEach { amount ->
            val request = createRequest().toMutableMap().apply { this["target_count_hundredths"] = amount; this["unit"] = "ml" }
            assertTrue(invoke(habitHandler(bridge), NativeMethodChannelHandler.MethodHabitCreate, request).map()["ok"] == true)
            assertEquals(amount, NativeContractJsonCodec.decodeObject(bridge.lastRequestJson!!)["target_count_hundredths"])
        }
    }

    @Test
    fun appearanceMethodsReturnSpecificInvalidAndStorageErrors() {
        val calls = executor()
        val store = RecordingAppearanceStore()
        val handler = AppearanceMethodHandler(store, calls)
        assertEquals("teal", data(invoke(handler, NativeMethodChannelHandler.MethodAppearanceGetLocal, emptyMap<String, Any?>()).map())["habit_progress_color"])
        listOf("teal", "blue", "indigo", "green", "orange", "rose", "purple").forEach { token ->
            assertEquals(token, data(invoke(handler, NativeMethodChannelHandler.MethodAppearanceUpdateLocal, mapOf("habit_progress_color" to token)).map())["habit_progress_color"])
            assertEquals(token, store.value)
        }
        val invalid = invoke(handler, NativeMethodChannelHandler.MethodAppearanceUpdateLocal, mapOf("habit_progress_color" to "#ff00ff")).map()
        assertEquals(NativeErrorCodes.AppearanceColorTokenInvalid, errorCode(invalid))

        store.fail = true
        val failed = invoke(handler, NativeMethodChannelHandler.MethodAppearanceUpdateLocal, mapOf("habit_progress_color" to "blue")).map()
        assertEquals(NativeErrorCodes.AppearanceStorageFailed, errorCode(failed))
    }

    private fun habitHandler(bridge: NativeHabitBridge): HabitMethodHandler {
        val calls = executor()
        return HabitMethodHandler(
            bridge,
            NativeContractProfile.V2,
            calls,
            HabitMutationOrchestrator(
                coordinator = null,
                capabilityProvider = AnniversaryCapabilityProvider {
                    AnniversaryCapabilitySnapshot("not_required", "not_required", true, true)
                },
                retryEnqueuer = null,
                logger = NativeBridgeLogger { _, _, _ -> },
            ),
        )
    }

    private fun executor() = NativeCallExecutor(
        Executor { it.run() },
        NativeContractProfile.V2,
        NativeBridgeLogger { _, _, _ -> },
    )

    private fun invoke(handler: ChannelMethodHandler, method: String, arguments: Any?): RecordingResult {
        val result = RecordingResult()
        handler.handle(MethodCall(method, arguments), SingleCompletion(result, ResultDispatcher { it() }))
        return result
    }

    /** Scripted Fake derived from contracts/fixtures/habit and sharing the production narrow interface. */
    private class FakeNativeHabitBridge : NativeHabitBridge {
        val calls = mutableListOf<String>()
        var lastRequestJson: String? = null
        private fun respond(method: String, requestJson: String, data: Any?): String {
            calls += method
            lastRequestJson = requestJson
            return success(data)
        }
        override fun createHabit(requestJson: String) = respond(NativeMethodChannelHandler.MethodHabitCreate, requestJson, mutationCommit())
        override fun updateHabit(requestJson: String) = respond(NativeMethodChannelHandler.MethodHabitUpdate, requestJson, mutationCommit())
        override fun listHabits(requestJson: String) = respond(NativeMethodChannelHandler.MethodHabitList, requestJson, listResponse())
        override fun getHabitDetail(requestJson: String) = respond(NativeMethodChannelHandler.MethodHabitDetail, requestJson, detail())
        override fun endHabit(requestJson: String) = respond(NativeMethodChannelHandler.MethodHabitEnd, requestJson, mutationCommit())
        override fun deleteHabit(requestJson: String) = respond(NativeMethodChannelHandler.MethodHabitDelete, requestJson, deleteCommit())
        override fun checkInHabit(requestJson: String) = respond(NativeMethodChannelHandler.MethodHabitCheckIn, requestJson, checkInCommit())
        override fun clearHabitCheckIn(requestJson: String) = respond(NativeMethodChannelHandler.MethodHabitClearCheckIn, requestJson, checkInCommit())
        override fun listHabitDailyStatuses(requestJson: String) = respond(NativeMethodChannelHandler.MethodHabitListDailyStatuses, requestJson, dailyStatusList())
        override fun setHabitReminder(requestJson: String) = respond(NativeMethodChannelHandler.MethodHabitSetReminder, requestJson, mutationCommit())
        override fun reconcileHabitReminders(requestJson: String): String = error("unused")
    }

    private class RecordingAppearanceStore : AppearancePreferencesStore {
        var value = "teal"
        var fail = false
        override fun getHabitProgressColor() = value
        override fun updateHabitProgressColor(token: String): String {
            if (fail) throw com.excellentcalendar.excellent_calendar.android.appearance.AppearanceStorageException("failed")
            value = token
            return token
        }
    }

    private class RecordingResult : MethodChannel.Result {
        private var value: Any? = null
        private var count = 0
        override fun success(result: Any?) { count += 1; value = result }
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = error("unexpected")
        override fun notImplemented() = error("unexpected")
        @Suppress("UNCHECKED_CAST") fun map(): Map<String, Any?> { assertEquals(1, count); return value as Map<String, Any?> }
    }

    companion object {
        private const val HabitId = "11111111-1111-4111-8111-111111111111"
        private const val RecurrenceId = "22222222-2222-4222-8222-222222222222"
        private const val CheckInId = "33333333-3333-4333-8333-333333333333"
        private const val Date = "2026-08-28"
        private const val Instant = "2026-08-28T01:00:00Z"
        private const val Timezone = "Asia/Shanghai"

        private fun createRequest() = linkedMapOf<String, Any?>(
            "title" to "Read", "description" to null, "category_id" to null,
            "recurrence" to linkedMapOf("frequency" to "daily", "interval" to 1, "timezone_mode" to "follow_device"),
            "target_count_hundredths" to null, "unit" to null, "start_date" to Date, "end_date" to "2026-09-30",
            "reminder" to disabledReminder(), "timezone" to Timezone,
        )
        private fun updateRequest() = LinkedHashMap(createRequest()).apply { remove("recurrence"); this["id"] = HabitId; this["expected_updated_at"] = Instant }
        private fun optimisticRequest() = linkedMapOf("id" to HabitId, "expected_updated_at" to Instant, "timezone" to Timezone)
        private fun checkInRequest() = linkedMapOf<String, Any?>("habit_id" to HabitId, "check_date" to Date, "status" to "done", "completed_count_hundredths" to null, "note" to null, "timezone" to Timezone)
        private fun disabledReminder() = linkedMapOf<String, Any?>("is_enabled" to false, "local_time" to null, "timezone_mode" to "follow_device", "method" to "popup")
        private fun success(data: Any?) = NativeContractJsonCodec.encodeObject(NativeResultContract.success(data, contractVersion = 2).toMap())
        private fun habit() = linkedMapOf<String, Any?>("id" to HabitId, "title" to "Read", "description" to null, "category_id" to null, "recurrence_id" to RecurrenceId, "target_count_hundredths" to null, "unit" to null, "start_date" to "2026-08-01", "end_date" to "2026-09-30", "ended_date" to null, "is_active" to true, "created_at" to Instant, "updated_at" to Instant, "deleted_at" to null)
        private fun recurrence() = linkedMapOf<String, Any?>("id" to RecurrenceId, "frequency" to "daily", "interval" to 1, "timezone_mode" to "follow_device", "created_at" to Instant, "updated_at" to Instant, "deleted_at" to null)
        private fun statistics(done: Int = 0) = linkedMapOf<String, Any?>("as_of_date" to Date, "elapsed_eligible_days" to 28, "done_days" to done, "skipped_days" to 0, "partial_days" to 0, "missed_days" to 0, "current_streak" to done, "longest_streak" to done, "completion_rate_7_days" to 0.0, "completion_rate_30_days" to 0.0, "completion_rate_all" to 0.0, "quantity_progress_rate_7_days" to null, "quantity_progress_rate_30_days" to null, "quantity_progress_rate_all" to null, "total_completed_count_hundredths" to null, "average_completed_count_per_eligible_day_hundredths" to null)
        private fun reminderSettings() = linkedMapOf<String, Any?>("is_enabled" to false, "template" to null, "active_reminder_count" to 0, "schedule_reconciliation_required" to false)
        private fun checkIn() = linkedMapOf<String, Any?>("id" to CheckInId, "habit_id" to HabitId, "check_date" to Date, "status" to "done", "completed_count_hundredths" to null, "target_count_snapshot_hundredths" to null, "unit_snapshot" to null, "completed_at" to Instant, "note" to null, "source" to "manual", "created_at" to Instant, "updated_at" to Instant, "deleted_at" to null)
        private fun daily(status: String = "absent") = linkedMapOf<String, Any?>("date" to Date, "status" to status, "is_final" to (status == "done"), "check_in" to if (status == "done") checkIn() else null, "completion_ratio" to if (status == "done") 1.0 else null)
        private fun detail() = linkedMapOf<String, Any?>("habit" to habit(), "recurrence" to recurrence(), "lifecycle_status" to "active", "statistics" to statistics(), "reminder_settings" to reminderSettings(), "today" to daily(), "history" to listOf(daily()), "history_start_date" to Date, "history_end_date" to Date, "has_earlier_history" to false, "has_ever_checked_in" to false, "latest_check_in_date" to null, "challenge_time_progress" to 0.5, "remaining_days" to 34)
        private fun mutationCommit() = linkedMapOf<String, Any?>("data_saved" to true, "detail" to detail(), "schedule_reconciliation_required" to false)
        private fun deleteCommit() = linkedMapOf<String, Any?>("data_saved" to true, "habit_id" to HabitId, "deleted_at" to Instant, "schedule_reconciliation_required" to false)
        private fun checkInCommit() = linkedMapOf<String, Any?>("data_saved" to true, "check_in" to checkIn(), "daily_status" to daily("done"), "statistics" to statistics(1), "reminder_settings" to reminderSettings(), "schedule_reconciliation_required" to false, "idempotent_replay" to false)
        private fun listResponse() = linkedMapOf<String, Any?>("items" to emptyList<Any?>(), "pagination" to linkedMapOf("total" to 0, "page" to 1, "page_size" to 20, "has_more" to false, "next_cursor" to null), "today_progress" to linkedMapOf("as_of_date" to Date, "active_count" to 0, "done_count" to 0, "eligible_count" to 0, "skipped_count" to 0, "partial_count" to 0, "absent_count" to 0))
        private fun dailyStatusList() = linkedMapOf<String, Any?>("habit_id" to HabitId, "start_date" to Date, "end_date" to Date, "items" to listOf(daily()))
        @Suppress("UNCHECKED_CAST") private fun data(result: Map<String, Any?>) = result["data"] as Map<String, Any?>
        @Suppress("UNCHECKED_CAST") private fun errorCode(result: Map<String, Any?>) = (result["error"] as Map<String, Any?>)["code"]
    }
}
