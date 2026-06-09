package com.excellentcalendar.excellent_calendar.bridge

import com.excellentcalendar.excellent_calendar.bridge.channel.NativeBridgeLogger
import com.excellentcalendar.excellent_calendar.bridge.channel.NativeMethodChannelHandler
import com.excellentcalendar.excellent_calendar.bridge.channel.ResultDispatcher
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.native.NativeEventBridge
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * NativeMethodChannelHandler 的单元测试。
 *
 * 这些测试不加载真实 C++ 动态库，而是用 FakeNativeEventBridge 模拟 native 返回。
 * 这样可以专注验证 Kotlin 层：请求校验、JSON 转换、响应合约校验、错误包装和回调行为。
 */
class NativeMethodChannelHandlerTest {
    @Test
    fun createEventSuccessForwardsSnakeCaseJsonAndNativeResult() {
        val nativeResponse = nativeResult(
            ok = true,
            data = eventResponse(
                id = "event-123",
                title = "Design review",
                content = "Room 8",
            ),
            error = null,
            requestId = "native-request-1",
        )
        val fakeBridge = FakeNativeEventBridge(createResponseJson = NativeContractJsonCodec.encodeObject(nativeResponse))
        val result = invoke(handler(fakeBridge), NativeMethodChannelHandler.MethodEventCreate, createEventArguments())

        val sentJson = fakeBridge.lastCreateRequestJson
        assertNotNull(sentJson)
        assertTrue(sentJson!!.contains("\"start_at\""))
        assertTrue(sentJson.contains("\"is_all_day\""))
        assertFalse(sentJson.contains("startAt"))
        assertFalse(sentJson.contains("isAllDay"))

        val sent = NativeContractJsonCodec.decodeObject(sentJson)
        assertEquals("Design review", sent["title"])
        assertEquals(null, sent["content"])
        assertEquals("2026-06-06T10:00:00Z", sent["start_at"])
        assertEquals("2026-06-06T11:00:00Z", sent["end_at"])
        assertEquals("manual", sent["source"])
        assertEquals("important_urgent", sent["importance"])

        @Suppress("UNCHECKED_CAST")
        val recurrence = sent["recurrence"] as Map<String, Any?>
        assertEquals("weekly", recurrence["frequency"])
        assertEquals(listOf(1, 3), recurrence["days_of_week"])
        assertEquals(null, recurrence["end_at"])

        @Suppress("UNCHECKED_CAST")
        val reminders = sent["reminders"] as List<Map<String, Any?>>
        assertEquals(1, reminders.size)
        assertEquals(null, reminders[0]["target_id"])
        assertEquals(listOf("popup", "ring"), reminders[0]["methods"])

        val returned = result.successMap()
        assertEquals(nativeResponse["ok"], returned["ok"])
        assertEquals(nativeResponse["data"], returned["data"])
        assertEquals(nativeResponse["error"], returned["error"])
        assertEquals(1, returned["contract_version"])
        assertEquals("native-request-1", returned["request_id"])
        assertFalse(result.errorCalled)
    }

    @Test
    fun createEventFailurePreservesBusinessErrorEnvelope() {
        val nativeResponse = nativeResult(
            ok = false,
            data = null,
            error = linkedMapOf(
                "code" to "EVENT_TIME_INVALID",
                "message" to "Event start time must be earlier than end time",
                "details" to linkedMapOf("field" to "start_at"),
                "retryable" to false,
            ),
            requestId = "native-request-2",
        )
        val fakeBridge = FakeNativeEventBridge(createResponseJson = NativeContractJsonCodec.encodeObject(nativeResponse))
        val result = invoke(handler(fakeBridge), NativeMethodChannelHandler.MethodEventCreate, createEventArguments())
        val returned = result.successMap()

        assertEquals(false, returned["ok"])
        assertNull(returned["data"])
        @Suppress("UNCHECKED_CAST")
        val error = returned["error"] as Map<String, Any?>
        assertEquals("EVENT_TIME_INVALID", error["code"])
        assertEquals("Event start time must be earlier than end time", error["message"])
        assertEquals(linkedMapOf("field" to "start_at"), error["details"])
        assertEquals(false, error["retryable"])
        assertEquals("native-request-2", returned["request_id"])
        assertFalse(result.errorCalled)
    }

    @Test
    fun searchEventsReturnsEmptyListWithPagination() {
        val nativeResponse = nativeResult(
            ok = true,
            data = eventListResponse(emptyList(), pagination(total = 0, page = 1, pageSize = 20, hasMore = false)),
            error = null,
            requestId = "search-empty",
        )
        val fakeBridge = FakeNativeEventBridge(searchResponseJson = NativeContractJsonCodec.encodeObject(nativeResponse))
        val result = invoke(handler(fakeBridge), NativeMethodChannelHandler.MethodEventSearch, searchArguments())

        val sent = NativeContractJsonCodec.decodeObject(fakeBridge.lastSearchRequestJson!!)
        assertEquals("2026-06-06T00:00:00Z", sent["start_at_from"])
        assertEquals(listOf("manual"), sent["source"])
        @Suppress("UNCHECKED_CAST")
        val sentPagination = sent["pagination"] as Map<String, Any?>
        assertEquals(20, sentPagination["page_size"])

        @Suppress("UNCHECKED_CAST")
        val data = result.successMap()["data"] as Map<String, Any?>
        assertEquals(emptyList<Any>(), data["items"])
        assertEquals(pagination(total = 0, page = 1, pageSize = 20, hasMore = false), data["pagination"])
    }

    @Test
    fun searchEventsReturnsSingleAndMultipleEventsWithNullOptionalFields() {
        val singleEvent = eventResponse(id = "event-1", content = null, categoryId = null)
        val multipleEvents = listOf(
            singleEvent,
            eventResponse(id = "event-2", title = "Coffee", importance = "important_noturgent"),
        )
        val nativeResponse = nativeResult(
            ok = true,
            data = eventListResponse(
                items = multipleEvents,
                pagination = pagination(total = 2, page = 1, pageSize = 2, hasMore = true, nextCursor = "cursor-2"),
            ),
            error = null,
            requestId = "search-many",
        )
        val fakeBridge = FakeNativeEventBridge(searchResponseJson = NativeContractJsonCodec.encodeObject(nativeResponse))
        val result = invoke(handler(fakeBridge), NativeMethodChannelHandler.MethodEventSearch, searchArguments(pageSize = 2))

        @Suppress("UNCHECKED_CAST")
        val data = result.successMap()["data"] as Map<String, Any?>
        @Suppress("UNCHECKED_CAST")
        val items = data["items"] as List<Map<String, Any?>>
        assertEquals(2, items.size)
        assertEquals(null, items[0]["content"])
        assertEquals(null, items[0]["category_id"])
        assertEquals("event-2", items[1]["id"])

        @Suppress("UNCHECKED_CAST")
        val returnedPagination = data["pagination"] as Map<String, Any?>
        assertEquals(2, returnedPagination["total"])
        assertEquals(2, returnedPagination["page_size"])
        assertEquals(true, returnedPagination["has_more"])
        assertEquals("cursor-2", returnedPagination["next_cursor"])
    }

    @Test
    fun malformedNativeSearchResponseReturnsNormalizedFailure() {
        val fakeBridge = FakeNativeEventBridge(
            searchResponseJson = NativeContractJsonCodec.encodeObject(
                linkedMapOf(
                    "ok" to true,
                    "data" to null,
                    "error" to linkedMapOf("code" to "EVENT_NOT_FOUND"),
                    "contract_version" to 1,
                    "request_id" to "bad-response",
                ),
            ),
        )
        val result = invoke(handler(fakeBridge), NativeMethodChannelHandler.MethodEventSearch, searchArguments())
        val returned = result.successMap()

        assertEquals(false, returned["ok"])
        assertNull(returned["data"])
        @Suppress("UNCHECKED_CAST")
        val error = returned["error"] as Map<String, Any?>
        assertEquals(NativeErrorCodes.ContractValidationFailed, error["code"])
        assertFalse(result.errorCalled)
    }

    @Test
    fun completeEventForwardsOccurrenceRequestAndValidatesStateResponse() {
        val nativeResponse = nativeResult(
            ok = true,
            data = occurrenceStateResponse(),
            error = null,
            requestId = "complete-occurrence",
        )
        val fakeBridge = FakeNativeEventBridge(
            completeResponseJson = NativeContractJsonCodec.encodeObject(nativeResponse),
        )
        val result = invoke(
            handler(fakeBridge),
            NativeMethodChannelHandler.MethodEventComplete,
            completeEventArguments(),
        )

        val sent = NativeContractJsonCodec.decodeObject(fakeBridge.lastCompleteRequestJson!!)
        assertEquals("event-123", sent["event_id"])
        assertEquals("2026-06-08T01:00:00Z", sent["occurrence_start_at"])
        assertEquals("2026-06-08T01:30:00Z", sent["completed_at"])
        assertEquals("manual", sent["source"])

        @Suppress("UNCHECKED_CAST")
        val data = result.successMap()["data"] as Map<String, Any?>
        assertEquals("completed", data["status"])
        assertEquals("2026-06-08T01:00:00Z", data["occurrence_start_at"])
        assertFalse(result.errorCalled)
    }

    @Test
    fun reopenEventForwardsOccurrenceRequestAndValidatesStateResponse() {
        val nativeResponse = nativeResult(
            ok = true,
            data = occurrenceStateResponse(deletedAt = "2026-06-08T02:00:00Z"),
            error = null,
            requestId = "reopen-occurrence",
        )
        val fakeBridge = FakeNativeEventBridge(
            reopenResponseJson = NativeContractJsonCodec.encodeObject(nativeResponse),
        )
        val result = invoke(
            handler(fakeBridge),
            NativeMethodChannelHandler.MethodEventReopen,
            reopenEventArguments(),
        )

        val sent = NativeContractJsonCodec.decodeObject(fakeBridge.lastReopenRequestJson!!)
        assertEquals("event-123", sent["event_id"])
        assertEquals("2026-06-08T01:00:00Z", sent["occurrence_start_at"])

        @Suppress("UNCHECKED_CAST")
        val data = result.successMap()["data"] as Map<String, Any?>
        assertEquals("2026-06-08T02:00:00Z", data["deleted_at"])
        assertFalse(result.errorCalled)
    }

    @Test
    fun jniUnavailableReturnsFailureWithoutFakeSuccess() {
        val fakeBridge = FakeNativeEventBridge(createError = UnsatisfiedLinkError("missing nativeCreateEvent"))
        val result = invoke(handler(fakeBridge), NativeMethodChannelHandler.MethodEventCreate, createEventArguments())
        val returned = result.successMap()

        assertEquals(false, returned["ok"])
        assertNull(returned["data"])
        @Suppress("UNCHECKED_CAST")
        val error = returned["error"] as Map<String, Any?>
        assertEquals(NativeErrorCodes.NativeInternalError, error["code"])
        assertEquals("Native event bridge is unavailable.", error["message"])
        assertFalse(result.errorCalled)
    }

    @Test
    fun unknownMethodIsNotImplemented() {
        val result = invoke(handler(FakeNativeEventBridge()), "event.read_calendar", searchArguments())

        assertTrue(result.notImplementedCalled)
        assertFalse(result.successCalled)
        assertFalse(result.errorCalled)
    }

    private fun handler(fakeBridge: FakeNativeEventBridge): NativeMethodChannelHandler {
        return NativeMethodChannelHandler(
            nativeEventBridge = fakeBridge,
            executor = Executor { command -> command.run() },
            resultDispatcher = ResultDispatcher { block -> block() },
            logger = NativeBridgeLogger { _, _, _ -> },
        )
    }

    private fun invoke(
        handler: NativeMethodChannelHandler,
        method: String,
        arguments: Map<String, Any?>,
    ): RecordingResult {
        val result = RecordingResult()
        handler.onMethodCall(MethodCall(method, arguments), result)
        return result
    }

    private fun createEventArguments(): Map<String, Any?> {
        return linkedMapOf(
            "title" to "Design review",
            "content" to null,
            "start_at" to "2026-06-06T10:00:00Z",
            "end_at" to "2026-06-06T11:00:00Z",
            "is_all_day" to false,
            "category_id" to "category-work",
            "importance" to "important_urgent",
            "location" to "Room 8",
            "timezone" to "Asia/Shanghai",
            "source" to "manual",
            "recurrence" to linkedMapOf(
                "frequency" to "weekly",
                "interval" to 1,
                "days_of_week" to listOf(1, 3),
                "day_of_month" to null,
                "month_of_year" to null,
                "start_at" to "2026-06-06T10:00:00Z",
                "end_at" to null,
                "count" to null,
                "timezone" to "Asia/Shanghai",
                "rrule" to null,
            ),
            "reminders" to listOf(
                linkedMapOf(
                    "target_type" to "event",
                    "target_id" to null,
                    "remind_at" to null,
                    "advance_minutes" to 30,
                    "methods" to listOf("popup", "ring"),
                    "message" to null,
                    "is_enabled" to true,
                    "source" to "manual",
                ),
            ),
        )
    }

    private fun searchArguments(pageSize: Int = 20): Map<String, Any?> {
        return linkedMapOf(
            "keyword" to null,
            "start_at_from" to "2026-06-06T00:00:00Z",
            "start_at_to" to "2026-06-07T00:00:00Z",
            "category_ids" to listOf("category-work"),
            "importance" to listOf("important_urgent"),
            "location" to null,
            "has_recurrence" to null,
            "source" to listOf("manual"),
            "include_deleted" to false,
            "pagination" to linkedMapOf(
                "page" to 1,
                "page_size" to pageSize,
                "cursor" to null,
                "sort_by" to null,
                "sort_direction" to "asc",
            ),
            "sort_by" to "start_at",
            "sort_direction" to "asc",
        )
    }

    private fun completeEventArguments(): Map<String, Any?> {
        return linkedMapOf(
            "event_id" to "event-123",
            "occurrence_start_at" to "2026-06-08T01:00:00Z",
            "completed_at" to "2026-06-08T01:30:00Z",
            "source" to "manual",
            "note" to "Finished from widget",
        )
    }

    private fun reopenEventArguments(): Map<String, Any?> {
        return linkedMapOf(
            "event_id" to "event-123",
            "occurrence_start_at" to "2026-06-08T01:00:00Z",
        )
    }

    private fun nativeResult(
        ok: Boolean,
        data: Any?,
        error: Map<String, Any?>?,
        requestId: String?,
    ): Map<String, Any?> {
        return linkedMapOf(
            "ok" to ok,
            "data" to data,
            "error" to error,
            "contract_version" to 1,
            "request_id" to requestId,
        )
    }

    private fun occurrenceStateResponse(
        deletedAt: String? = null,
    ): Map<String, Any?> {
        return linkedMapOf(
            "id" to "state-123",
            "event_id" to "event-123",
            "occurrence_start_at" to "2026-06-08T01:00:00Z",
            "status" to "completed",
            "completed_at" to "2026-06-08T01:30:00Z",
            "note" to "Finished from widget",
            "source" to "manual",
            "created_at" to "2026-06-08T01:30:00Z",
            "updated_at" to "2026-06-08T01:30:00Z",
            "deleted_at" to deletedAt,
        )
    }

    private fun eventListResponse(
        items: List<Map<String, Any?>>,
        pagination: Map<String, Any?>,
    ): Map<String, Any?> {
        return linkedMapOf(
            "items" to items,
            "pagination" to pagination,
        )
    }

    private fun eventResponse(
        id: String,
        title: String = "Design review",
        content: String? = "Notes",
        categoryId: String? = "category-work",
        importance: String? = "important_urgent",
    ): Map<String, Any?> {
        return linkedMapOf(
            "id" to id,
            "title" to title,
            "content" to content,
            "start_at" to "2026-06-06T10:00:00Z",
            "end_at" to "2026-06-06T11:00:00Z",
            "is_all_day" to false,
            "has_recurrence" to false,
            "status" to "active",
            "completed_at" to null,
            "recurrence_id" to null,
            "category_id" to categoryId,
            "importance" to importance,
            "location" to "Room 8",
            "timezone" to "Asia/Shanghai",
            "source" to "manual",
            "created_at" to "2026-06-06T09:00:00Z",
            "updated_at" to "2026-06-06T09:00:00Z",
            "deleted_at" to null,
        )
    }

    private fun pagination(
        total: Int,
        page: Int,
        pageSize: Int,
        hasMore: Boolean,
        nextCursor: String? = null,
    ): Map<String, Any?> {
        return linkedMapOf(
            "total" to total,
            "page" to page,
            "page_size" to pageSize,
            "has_more" to hasMore,
            "next_cursor" to nextCursor,
        )
    }

    /**
     * 假 native bridge。
     *
     * 它记录 Kotlin 发给 native 的 JSON，并返回测试预设的 NativeResult JSON。
     * 这是一种常见测试手法：用 fake 隔离外部依赖，让单元测试稳定、快速。
     */
    private class FakeNativeEventBridge(
        private val createResponseJson: String = NativeContractJsonCodec.encodeObject(
            linkedMapOf(
                "ok" to true,
                "data" to eventResponseStatic(),
                "error" to null,
                "contract_version" to 1,
                "request_id" to "default",
            ),
        ),
        private val searchResponseJson: String = NativeContractJsonCodec.encodeObject(
            linkedMapOf(
                "ok" to true,
                "data" to linkedMapOf(
                    "items" to emptyList<Any>(),
                    "pagination" to linkedMapOf(
                        "total" to 0,
                        "page" to 1,
                        "page_size" to 20,
                        "has_more" to false,
                        "next_cursor" to null,
                    ),
                ),
                "error" to null,
                "contract_version" to 1,
                "request_id" to "default",
            ),
        ),
        private val completeResponseJson: String = NativeContractJsonCodec.encodeObject(
            linkedMapOf(
                "ok" to true,
                "data" to occurrenceStateResponseStatic(),
                "error" to null,
                "contract_version" to 1,
                "request_id" to "default",
            ),
        ),
        private val reopenResponseJson: String = NativeContractJsonCodec.encodeObject(
            linkedMapOf(
                "ok" to true,
                "data" to occurrenceStateResponseStatic(deletedAt = "2026-06-08T02:00:00Z"),
                "error" to null,
                "contract_version" to 1,
                "request_id" to "default",
            ),
        ),
        private val createError: Throwable? = null,
    ) : NativeEventBridge {
        var lastCreateRequestJson: String? = null
            private set
        var lastSearchRequestJson: String? = null
            private set
        var lastCompleteRequestJson: String? = null
            private set
        var lastReopenRequestJson: String? = null
            private set

        override fun createEvent(requestJson: String): String {
            lastCreateRequestJson = requestJson
            createError?.let { throw it }
            return createResponseJson
        }

        override fun searchEvents(requestJson: String): String {
            lastSearchRequestJson = requestJson
            return searchResponseJson
        }

        override fun completeEvent(requestJson: String): String {
            lastCompleteRequestJson = requestJson
            return completeResponseJson
        }

        override fun reopenEvent(requestJson: String): String {
            lastReopenRequestJson = requestJson
            return reopenResponseJson
        }

        companion object {
            private fun eventResponseStatic(): Map<String, Any?> {
                return linkedMapOf(
                    "id" to "event-default",
                    "title" to "Default",
                    "content" to null,
                    "start_at" to "2026-06-06T10:00:00Z",
                    "end_at" to "2026-06-06T11:00:00Z",
                    "is_all_day" to false,
                    "has_recurrence" to false,
                    "status" to "active",
                    "completed_at" to null,
                    "recurrence_id" to null,
                    "category_id" to null,
                    "importance" to null,
                    "location" to null,
                    "timezone" to null,
                    "source" to "manual",
                    "created_at" to "2026-06-06T09:00:00Z",
                    "updated_at" to "2026-06-06T09:00:00Z",
                    "deleted_at" to null,
                )
            }

            private fun occurrenceStateResponseStatic(
                deletedAt: String? = null,
            ): Map<String, Any?> {
                return linkedMapOf(
                    "id" to "state-default",
                    "event_id" to "event-default",
                    "occurrence_start_at" to "2026-06-08T01:00:00Z",
                    "status" to "completed",
                    "completed_at" to "2026-06-08T01:30:00Z",
                    "note" to null,
                    "source" to "manual",
                    "created_at" to "2026-06-08T01:30:00Z",
                    "updated_at" to "2026-06-08T01:30:00Z",
                    "deleted_at" to deletedAt,
                )
            }
        }
    }

    /**
     * 记录 MethodChannel.Result 回调情况。
     *
     * Flutter 的真实 result 会把数据送回 Dart；测试里只需要记录 success/error/notImplemented
     * 哪个被调用，以及 success 的值是什么。
     */
    private class RecordingResult : MethodChannel.Result {
        var successValue: Any? = null
            private set
        var successCalled = false
            private set
        var errorCalled = false
            private set
        var notImplementedCalled = false
            private set

        override fun success(result: Any?) {
            successCalled = true
            successValue = result
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            errorCalled = true
        }

        override fun notImplemented() {
            notImplementedCalled = true
        }

        fun successMap(): Map<String, Any?> {
            assertTrue(successCalled)
            @Suppress("UNCHECKED_CAST")
            return successValue as Map<String, Any?>
        }
    }
}
