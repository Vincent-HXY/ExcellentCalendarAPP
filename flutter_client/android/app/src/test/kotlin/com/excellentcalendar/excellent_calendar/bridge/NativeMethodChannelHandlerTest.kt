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
        private val createError: Throwable? = null,
    ) : NativeEventBridge {
        var lastCreateRequestJson: String? = null
            private set
        var lastSearchRequestJson: String? = null
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
        }
    }

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
