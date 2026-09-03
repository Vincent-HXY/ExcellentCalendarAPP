package com.excellentcalendar.excellent_calendar.bridge

import com.excellentcalendar.excellent_calendar.android.search.SearchHistorySnapshot
import com.excellentcalendar.excellent_calendar.android.search.SearchHistoryStore
import com.excellentcalendar.excellent_calendar.android.search.SearchHistoryStoreResult
import com.excellentcalendar.excellent_calendar.bridge.channel.NativeBridgeLogger
import com.excellentcalendar.excellent_calendar.bridge.channel.NativeMethodChannelHandler
import com.excellentcalendar.excellent_calendar.bridge.channel.ResultDispatcher
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.native.NativeCalendarCoreBridge
import com.excellentcalendar.excellent_calendar.bridge.native.NativeContractProfile
import com.excellentcalendar.excellent_calendar.bridge.native.NativeSearchBridge
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
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

class SearchMethodChannelHandlerTest {
    @Test
    fun threeMethodsShareOneHandlerAndRouteQueryOnlyToTheNarrowBridge() {
        val bridge = RecordingSearchBridge()
        val store = RecordingHistoryStore()
        val handler = handler(bridge, store)

        val query = invoke(handler, NativeMethodChannelHandler.MethodSearchQuery, queryRequest())
        val history = invoke(handler, NativeMethodChannelHandler.MethodSearchGetLocalHistory, emptyMap<String, Any?>())
        val replace = invoke(
            handler,
            NativeMethodChannelHandler.MethodSearchReplaceLocalHistory,
            linkedMapOf("expected_revision" to 3, "items" to listOf("项目 MEETING", "年度回顾")),
        )

        assertEquals(true, query.successMap()["ok"])
        assertEquals(true, history.successMap()["ok"])
        assertEquals(true, replace.successMap()["ok"])
        assertEquals(listOf(queryRequest()), bridge.requests)
        assertEquals(listOf("get", "replace:3"), store.calls)
        listOf(query, history, replace).forEach { assertEquals(1, it.successCount) }
    }

    @Test
    fun invalidShapeSemanticCursorTimezoneAndHistoryPayloadNeverReachOperations() {
        val bridge = RecordingSearchBridge()
        val store = RecordingHistoryStore()
        val handler = handler(bridge, store)
        val cases = listOf(
            queryRequest().toMutableMap().also { it["extra"] = true } to NativeErrorCodes.ContractValidationFailed,
            fixture("query_blank.semantic_invalid.json") to NativeErrorCodes.SearchQueryInvalid,
            fixture("query_bad_cursor.invalid.json") to NativeErrorCodes.SearchCursorInvalid,
            queryRequest().toMutableMap().also { it["timezone"] = "Mars/Olympus" } to NativeErrorCodes.TimezoneIdInvalid,
        )
        cases.forEach { (arguments, expected) ->
            assertEquals(expected, invoke(handler, NativeMethodChannelHandler.MethodSearchQuery, arguments).errorCode())
        }
        assertEquals(
            NativeErrorCodes.ContractValidationFailed,
            invoke(
                handler,
                NativeMethodChannelHandler.MethodSearchReplaceLocalHistory,
                linkedMapOf("expected_revision" to 3, "items" to listOf("Meeting", "meeting")),
            ).errorCode(),
        )
        assertTrue(bridge.requests.isEmpty())
        assertTrue(store.calls.isEmpty())
    }

    @Test
    fun nativeFailureMetadataIsPreservedAndMalformedSuccessFailsClosed() {
        val failureBridge = RecordingSearchBridge(
            override = nativeFailure(NativeErrorCodes.SearchCursorExpired, retryable = true),
        )
        val failure = invoke(handler(failureBridge, RecordingHistoryStore()), NativeMethodChannelHandler.MethodSearchQuery, queryRequest())
        assertEquals(NativeErrorCodes.SearchCursorExpired, failure.errorCode())
        @Suppress("UNCHECKED_CAST")
        val error = failure.successMap()["error"] as Map<String, Any?>
        assertEquals(true, error["retryable"])
        assertEquals(mapOf("cursor" to "expired"), error["details"])

        val malformedData = queryResponse().toMutableMap().also { it["query_generation"] = 99 }
        val malformedBridge = RecordingSearchBridge(override = nativeSuccess(malformedData))
        val malformed = invoke(handler(malformedBridge, RecordingHistoryStore()), NativeMethodChannelHandler.MethodSearchQuery, queryRequest())
        assertEquals(NativeErrorCodes.ContractValidationFailed, malformed.errorCode())
        assertEquals(1, malformed.successCount)
        assertFalse(malformed.errorCalled)
    }

    @Test
    fun historyConflictAndStorageFailureUseFrozenRetryableErrorsWithoutPayloadDetails() {
        val conflictStore = RecordingHistoryStore(
            replaceResult = SearchHistoryStoreResult.Failure(
                NativeErrorCodes.SearchHistoryConflict,
                "History conflict",
                "revision_mismatch",
                true,
            ),
        )
        val conflict = invoke(
            handler(RecordingSearchBridge(), conflictStore),
            NativeMethodChannelHandler.MethodSearchReplaceLocalHistory,
            linkedMapOf("expected_revision" to 3, "items" to listOf("项目")),
        )
        assertEquals(NativeErrorCodes.SearchHistoryConflict, conflict.errorCode())
        @Suppress("UNCHECKED_CAST")
        val details = ((conflict.successMap()["error"] as Map<String, Any?>)["details"] as Map<String, Any?>)
        assertEquals(mapOf("reason" to "revision_mismatch"), details)
        assertTrue(details.values.none { it.toString().contains("项目") })
    }

    @Test
    fun queryAndDiskOperationsRunOffCallerThreadAndCompleteExactlyOnce() {
        val executor = Executors.newSingleThreadExecutor { runnable -> Thread(runnable, "search-worker") }
        try {
            val bridge = RecordingSearchBridge()
            val store = RecordingHistoryStore()
            val handler = handler(bridge, store, executor)
            val caller = Thread.currentThread().name
            val query = invoke(handler, NativeMethodChannelHandler.MethodSearchQuery, queryRequest())
            val history = invoke(handler, NativeMethodChannelHandler.MethodSearchGetLocalHistory, emptyMap<String, Any?>())

            assertEquals(listOf("search-worker"), bridge.threads)
            assertTrue(store.threads.all { it == "search-worker" })
            assertNotEquals(caller, bridge.threads.single())
            assertEquals(1, query.successCount)
            assertEquals(1, history.successCount)
        } finally {
            executor.shutdownNow()
        }
    }

    @Test
    fun missingStoreV1ProfileAndRejectedExecutorFailWithoutFallback() {
        val missingStore = invoke(
            handler(RecordingSearchBridge(), null),
            NativeMethodChannelHandler.MethodSearchGetLocalHistory,
            emptyMap<String, Any?>(),
        )
        assertEquals(NativeErrorCodes.NativeInternalError, missingStore.errorCode())

        val v1Bridge = RecordingSearchBridge()
        val v1 = invoke(
            handler(v1Bridge, RecordingHistoryStore(), profile = NativeContractProfile.V1),
            NativeMethodChannelHandler.MethodSearchQuery,
            queryRequest(),
        )
        assertEquals(NativeErrorCodes.FeatureNotImplemented, v1.errorCode())
        assertTrue(v1Bridge.requests.isEmpty())

        val executor = Executors.newSingleThreadExecutor()
        val closed = handler(RecordingSearchBridge(), RecordingHistoryStore(), executor)
        closed.close()
        val rejected = invoke(closed, NativeMethodChannelHandler.MethodSearchQuery, queryRequest())
        assertEquals(NativeErrorCodes.NativeInternalError, rejected.errorCode())
        assertEquals(1, rejected.successCount)
    }

    private fun handler(
        bridge: NativeSearchBridge,
        store: SearchHistoryStore?,
        executor: Executor = Executor { it.run() },
        profile: NativeContractProfile = NativeContractProfile.V2,
    ) = NativeMethodChannelHandler(
        nativeCalendarCoreBridge = unusedAggregateBridge(),
        nativeSearchBridge = bridge,
        searchHistoryStore = store,
        contractProfile = profile,
        executor = executor,
        resultDispatcher = ResultDispatcher { it() },
        logger = NativeBridgeLogger { _, _, _ -> },
    )

    private fun invoke(handler: NativeMethodChannelHandler, method: String, arguments: Any?): RecordingResult =
        RecordingResult().also {
            handler.onMethodCall(MethodCall(method, arguments), it)
            assertTrue("method=$method", it.completed.await(5, TimeUnit.SECONDS))
        }

    private class RecordingSearchBridge(private val override: String? = null) : NativeSearchBridge {
        val requests = mutableListOf<Map<String, Any?>>()
        val threads = mutableListOf<String>()

        override fun querySearch(requestJson: String): String {
            requests += NativeContractJsonCodec.decodeObject(requestJson)
            threads += Thread.currentThread().name
            return override ?: nativeSuccess(queryResponse())
        }
    }

    private class RecordingHistoryStore(
        private val getResult: SearchHistoryStoreResult = SearchHistoryStoreResult.Success(
            SearchHistorySnapshot(3, listOf("项目 MEETING")),
        ),
        private val replaceResult: SearchHistoryStoreResult = SearchHistoryStoreResult.Success(
            SearchHistorySnapshot(4, listOf("项目 MEETING", "年度回顾")),
        ),
    ) : SearchHistoryStore {
        val calls = mutableListOf<String>()
        val threads = mutableListOf<String>()

        override fun get(): SearchHistoryStoreResult {
            calls += "get"
            threads += Thread.currentThread().name
            return getResult
        }

        override fun replace(expectedRevision: Long, items: List<String>): SearchHistoryStoreResult {
            calls += "replace:$expectedRevision"
            threads += Thread.currentThread().name
            return replaceResult
        }
    }

    private class RecordingResult : MethodChannel.Result {
        val completed = CountDownLatch(1)
        var successValue: Any? = null
        var successCount = 0
        var errorCalled = false

        override fun success(result: Any?) {
            successCount += 1
            successValue = result
            completed.countDown()
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            errorCalled = true
            completed.countDown()
        }

        override fun notImplemented() = completed.countDown()

        @Suppress("UNCHECKED_CAST")
        fun successMap(): Map<String, Any?> = successValue as Map<String, Any?>

        @Suppress("UNCHECKED_CAST")
        fun errorCode(): String = ((successMap()["error"] as Map<String, Any?>)["code"] as String)
    }

    companion object {
        private val fixtureDirectories = listOf(
            File("../../../contracts/fixtures/search"),
            File("../../contracts/fixtures/search"),
            File("../contracts/fixtures/search"),
            File("contracts/fixtures/search"),
        )

        private fun fixture(name: String): Map<String, Any?> {
            val directory = fixtureDirectories.firstOrNull(File::isDirectory)
                ?: error("Cannot locate Search fixtures")
            return NativeContractJsonCodec.decodeObject(File(directory, name).readText(Charsets.UTF_8))
        }

        private fun queryRequest(): Map<String, Any?> = fixture("query_three_sections.valid.json")
        private fun queryResponse(): Map<String, Any?> = fixture("query_response_three_types.valid.json")

        private fun nativeSuccess(data: Any?): String = NativeContractJsonCodec.encodeObject(
            linkedMapOf(
                "ok" to true,
                "data" to data,
                "error" to null,
                "contract_version" to 2,
                "request_id" to "search-request",
            ),
        )

        private fun nativeFailure(code: String, retryable: Boolean): String = NativeContractJsonCodec.encodeObject(
            linkedMapOf(
                "ok" to false,
                "data" to null,
                "error" to linkedMapOf(
                    "code" to code,
                    "message" to "Search query failed",
                    "details" to linkedMapOf("cursor" to "expired"),
                    "retryable" to retryable,
                ),
                "contract_version" to 2,
                "request_id" to "search-failure",
            ),
        )

        private fun unusedAggregateBridge(): NativeCalendarCoreBridge = Proxy.newProxyInstance(
            NativeCalendarCoreBridge::class.java.classLoader,
            arrayOf(NativeCalendarCoreBridge::class.java),
        ) { _, method, _ -> throw AssertionError("Unexpected aggregate call: ${method.name}") } as NativeCalendarCoreBridge
    }
}
