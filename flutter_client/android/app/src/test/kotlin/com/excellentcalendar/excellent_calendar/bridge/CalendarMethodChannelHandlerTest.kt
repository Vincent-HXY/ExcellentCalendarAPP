package com.excellentcalendar.excellent_calendar.bridge

import com.excellentcalendar.excellent_calendar.bridge.channel.NativeBridgeLogger
import com.excellentcalendar.excellent_calendar.bridge.channel.NativeMethodChannelHandler
import com.excellentcalendar.excellent_calendar.bridge.channel.ResultDispatcher
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.native.NativeCalendarCoreBridge
import com.excellentcalendar.excellent_calendar.bridge.native.NativeCalendarViewBridge
import com.excellentcalendar.excellent_calendar.bridge.native.NativeContractProfile
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.reflect.Proxy
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CalendarMethodChannelHandlerTest {
    @Test
    fun bothMethodsRouteToTheNarrowBridgeAndPreserveExactRequestJson() {
        val bridge = RecordingCalendarViewBridge()
        val handler = handler(bridge)
        val range = rangeRequest()
        val day = dayRequest()

        val rangeResult = invoke(handler, NativeMethodChannelHandler.MethodCalendarRangeSummary, range)
        val dayResult = invoke(handler, NativeMethodChannelHandler.MethodCalendarListDayItems, day)

        assertEquals(true, rangeResult.successMap()["ok"])
        assertEquals(true, dayResult.successMap()["ok"])
        assertEquals(listOf("range", "day"), bridge.calls.map { it.first })
        assertEquals(listOf(range, day), bridge.calls.map { it.second })
        assertEquals(1, rangeResult.successCount)
        assertEquals(1, dayResult.successCount)
    }

    @Test
    fun invalidRangeSnapshotCursorTimezoneAndUnknownFieldFailBeforeNative() {
        val bridge = RecordingCalendarViewBridge()
        val handler = handler(bridge)
        val cases = listOf(
            Triple(
                NativeMethodChannelHandler.MethodCalendarRangeSummary,
                rangeRequest().toMutableMap().also { it["range_end_date"] = "2026-08-31" },
                NativeErrorCodes.CalendarRangeInvalid,
            ),
            Triple(
                NativeMethodChannelHandler.MethodCalendarListDayItems,
                dayRequest().toMutableMap().also { it["snapshot_token"] = "bad" },
                NativeErrorCodes.CalendarSnapshotInvalid,
            ),
            Triple(
                NativeMethodChannelHandler.MethodCalendarListDayItems,
                dayRequest().toMutableMap().also { it["cursor"] = "bad" },
                NativeErrorCodes.CalendarCursorInvalid,
            ),
            Triple(
                NativeMethodChannelHandler.MethodCalendarListDayItems,
                dayRequest().toMutableMap().also { it["timezone"] = "Mars/Olympus" },
                NativeErrorCodes.TimezoneIdInvalid,
            ),
            Triple(
                NativeMethodChannelHandler.MethodCalendarListDayItems,
                dayRequest().toMutableMap().also { it["extra"] = true },
                NativeErrorCodes.ContractValidationFailed,
            ),
        )

        cases.forEach { (method, request, errorCode) ->
            assertEquals(errorCode, invoke(handler, method, request).errorCode())
        }
        assertTrue(bridge.calls.isEmpty())
    }

    @Test
    fun nativeCalendarErrorsPreserveEnvelopeDetailsAndRetryable() {
        val bridge = RecordingCalendarViewBridge(
            dayOverride = nativeFailure(
                code = NativeErrorCodes.CalendarSnapshotExpired,
                requestId = "expired-request",
                retryable = true,
            ),
        )
        val result = invoke(
            handler(bridge),
            NativeMethodChannelHandler.MethodCalendarListDayItems,
            dayRequest(),
        )

        assertFalse(result.errorCalled)
        assertEquals(false, result.successMap()["ok"])
        assertEquals(NativeErrorCodes.CalendarSnapshotExpired, result.errorCode())
        assertEquals("expired-request", result.successMap()["request_id"])
        @Suppress("UNCHECKED_CAST")
        val error = result.successMap()["error"] as Map<String, Any?>
        assertEquals(true, error["retryable"])
        assertEquals(mapOf("snapshot" to "stale"), error["details"])
    }

    @Test
    fun malformedNativeSuccessBecomesContractFailureExactlyOnce() {
        val malformedPage = dayPage().toMutableMap().also { it["section"] = "habit" }
        val bridge = RecordingCalendarViewBridge(dayOverride = nativeSuccess(malformedPage, "malformed"))
        val result = invoke(
            handler(bridge),
            NativeMethodChannelHandler.MethodCalendarListDayItems,
            dayRequest(),
        )

        assertEquals(NativeErrorCodes.ContractValidationFailed, result.errorCode())
        assertEquals(1, result.successCount)
        assertFalse(result.errorCalled)
    }

    @Test
    fun nativeLinkFailureBecomesStableInternalFailureExactlyOnce() {
        val bridge = object : NativeCalendarViewBridge {
            override fun calendarRangeSummary(requestJson: String): String =
                throw UnsatisfiedLinkError("missing Calendar symbol")
        }
        val result = invoke(
            handler(bridge),
            NativeMethodChannelHandler.MethodCalendarRangeSummary,
            rangeRequest(),
        )

        assertEquals(NativeErrorCodes.NativeInternalError, result.errorCode())
        assertEquals(1, result.successCount)
        assertFalse(result.errorCalled)
    }

    @Test
    fun nativeQueriesRunOffCallerThreadAndDispatchOneCompletion() {
        val executor = Executors.newSingleThreadExecutor { runnable -> Thread(runnable, "calendar-query-worker") }
        try {
            val bridge = RecordingCalendarViewBridge()
            val result = RecordingResult()
            val callerThread = Thread.currentThread().name
            handler(bridge, executor).onMethodCall(
                MethodCall(NativeMethodChannelHandler.MethodCalendarRangeSummary, rangeRequest()),
                result,
            )

            assertTrue(result.completed.await(5, TimeUnit.SECONDS))
            assertEquals("calendar-query-worker", bridge.threads.single())
            assertNotEquals(callerThread, bridge.threads.single())
            assertEquals(1, result.successCount)
        } finally {
            executor.shutdownNow()
        }
    }

    @Test
    fun v1ProfileReturnsStableFeatureFailureWithoutCallingNative() {
        val bridge = RecordingCalendarViewBridge()
        val result = invoke(
            handler(bridge, profile = NativeContractProfile.V1),
            NativeMethodChannelHandler.MethodCalendarRangeSummary,
            rangeRequest(),
        )

        assertEquals(NativeErrorCodes.FeatureNotImplemented, result.errorCode())
        assertTrue(bridge.calls.isEmpty())
    }

    private fun handler(
        bridge: NativeCalendarViewBridge,
        executor: Executor = Executor { command -> command.run() },
        profile: NativeContractProfile = NativeContractProfile.V2,
    ) = NativeMethodChannelHandler(
        nativeCalendarCoreBridge = unusedAggregateBridge(),
        nativeCalendarViewBridge = bridge,
        contractProfile = profile,
        executor = executor,
        resultDispatcher = ResultDispatcher { block -> block() },
        logger = NativeBridgeLogger { _, _, _ -> },
    )

    private fun invoke(
        handler: NativeMethodChannelHandler,
        method: String,
        arguments: Map<String, Any?>,
    ): RecordingResult = RecordingResult().also {
        handler.onMethodCall(MethodCall(method, arguments), it)
        assertTrue(it.completed.await(5, TimeUnit.SECONDS))
    }

    private class RecordingCalendarViewBridge(
        private val rangeOverride: String? = null,
        private val dayOverride: String? = null,
    ) : NativeCalendarViewBridge {
        val calls = mutableListOf<Pair<String, Map<String, Any?>>>()
        val threads = mutableListOf<String>()

        override fun calendarRangeSummary(requestJson: String): String {
            record("range", requestJson)
            return rangeOverride ?: nativeSuccess(rangeResponse(), "range-request")
        }

        override fun calendarListDayItems(requestJson: String): String {
            record("day", requestJson)
            return dayOverride ?: nativeSuccess(dayPage(), "day-request")
        }

        private fun record(operation: String, requestJson: String) {
            threads += Thread.currentThread().name
            calls += operation to NativeContractJsonCodec.decodeObject(requestJson)
        }
    }

    private class RecordingResult : MethodChannel.Result {
        val completed = CountDownLatch(1)
        var successValue: Any? = null
            private set
        var successCount = 0
            private set
        var errorCalled = false
            private set

        override fun success(result: Any?) {
            successCount += 1
            successValue = result
            completed.countDown()
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            errorCalled = true
            completed.countDown()
        }

        override fun notImplemented() {
            completed.countDown()
        }

        @Suppress("UNCHECKED_CAST")
        fun successMap(): Map<String, Any?> = successValue as Map<String, Any?>

        @Suppress("UNCHECKED_CAST")
        fun errorCode(): String = ((successMap()["error"] as Map<String, Any?>)["code"] as String)
    }

    companion object {
        private const val Snapshot = "calsnap1.ABCDEFGHIJKLMNOPQRST"

        private fun rangeRequest(): Map<String, Any?> = linkedMapOf(
            "range_start_date" to "2026-08-31",
            "range_end_date" to "2026-09-02",
            "timezone" to "Asia/Shanghai",
        )

        private fun dayRequest(): Map<String, Any?> = linkedMapOf(
            "date" to "2026-09-01",
            "timezone" to "Asia/Shanghai",
            "section" to "event",
            "snapshot_token" to Snapshot,
            "cursor" to null,
            "page_size" to 20,
        )

        private fun rangeResponse(): Map<String, Any?> = linkedMapOf(
            *rangeRequest().entries.map { it.key to it.value }.toTypedArray(),
            "snapshot_token" to Snapshot,
            "days" to listOf(
                daySummary("2026-08-31"),
                daySummary("2026-09-01"),
            ),
        )

        private fun daySummary(date: String): Map<String, Any?> = linkedMapOf(
            "date" to date,
            "has_open_event" to false,
            "has_pending_habit" to false,
            "has_anniversary" to false,
        )

        private fun dayPage(): Map<String, Any?> = linkedMapOf(
            "date" to "2026-09-01",
            "timezone" to "Asia/Shanghai",
            "section" to "event",
            "snapshot_token" to Snapshot,
            "page_size" to 20,
            "items" to listOf(
                linkedMapOf(
                    "event_id" to "11111111-1111-4111-8111-111111111111",
                    "title" to "Unicode 日历🗓️",
                    "is_all_day" to true,
                    "is_recurring" to false,
                    "recurrence_revision" to null,
                    "occurrence_key" to null,
                    "occurrence_start_at" to null,
                    "occurrence_start_date" to null,
                    "start_at" to null,
                    "end_at" to null,
                    "start_date" to "2026-09-01",
                    "end_date" to "2026-09-02",
                    "day_display" to "all_day",
                    "display_local_time" to null,
                    "status" to "pending",
                    "has_active_reminder" to false,
                ),
            ),
            "has_more" to false,
            "next_cursor" to null,
        )

        private fun nativeSuccess(data: Any?, requestId: String): String =
            NativeContractJsonCodec.encodeObject(
                linkedMapOf(
                    "ok" to true,
                    "data" to data,
                    "error" to null,
                    "contract_version" to 2,
                    "request_id" to requestId,
                ),
            )

        private fun nativeFailure(code: String, requestId: String, retryable: Boolean): String =
            NativeContractJsonCodec.encodeObject(
                linkedMapOf(
                    "ok" to false,
                    "data" to null,
                    "error" to linkedMapOf(
                        "code" to code,
                        "message" to "Calendar query failed",
                        "details" to linkedMapOf("snapshot" to "stale"),
                        "retryable" to retryable,
                    ),
                    "contract_version" to 2,
                    "request_id" to requestId,
                ),
            )

        private fun unusedAggregateBridge(): NativeCalendarCoreBridge =
            Proxy.newProxyInstance(
                NativeCalendarCoreBridge::class.java.classLoader,
                arrayOf(NativeCalendarCoreBridge::class.java),
            ) { _, method, _ ->
                throw AssertionError("Unexpected aggregate bridge call: ${method.name}")
            } as NativeCalendarCoreBridge
    }
}
