package com.excellentcalendar.excellent_calendar.bridge

import com.excellentcalendar.excellent_calendar.bridge.channel.NativeBridgeLogger
import com.excellentcalendar.excellent_calendar.bridge.channel.NativeMethodChannelHandler
import com.excellentcalendar.excellent_calendar.bridge.channel.ResultDispatcher
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.native.NativeAnniversaryBridge
import com.excellentcalendar.excellent_calendar.bridge.native.NativeCalendarCoreBridge
import com.excellentcalendar.excellent_calendar.bridge.native.NativeContractProfile
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.reflect.Proxy
import java.util.concurrent.Executor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AnniversaryMethodChannelHandlerTest {
    @Test
    fun everyAnniversaryMethodRoutesToItsNarrowBridgeAndPreservesRequestJson() {
        val bridge = RecordingAnniversaryBridge()
        val cases = listOf(
            Case(NativeMethodChannelHandler.MethodAnniversaryCreate, createRequest(), "create"),
            Case(NativeMethodChannelHandler.MethodAnniversaryUpdate, updateRequest(), "update"),
            Case(NativeMethodChannelHandler.MethodAnniversaryDelete, mapOf("id" to AnniversaryId), "delete"),
            Case(
                NativeMethodChannelHandler.MethodAnniversaryDetail,
                mapOf("id" to AnniversaryId, "timezone" to "Asia/Shanghai"),
                "detail",
            ),
            Case(NativeMethodChannelHandler.MethodAnniversaryList, listRequest(), "list"),
            Case(
                NativeMethodChannelHandler.MethodAnniversaryPreviewCountdown,
                linkedMapOf(
                    "date" to "2020-02-29",
                    "calendar_type" to "solar",
                    "recurrence" to linkedMapOf("frequency" to "yearly", "interval" to 1),
                    "timezone" to "Asia/Shanghai",
                ),
                "preview",
            ),
        )

        cases.forEach { case ->
            val result = invoke(handler(bridge), case.method, case.arguments)
            assertTrue("${case.method} should return NativeResult", result.successCalled)
            assertEquals(true, result.successMap()["ok"])
        }

        assertEquals(cases.map { it.bridgeOperation }, bridge.calls.map { it.first })
        cases.zip(bridge.calls).forEach { (case, call) ->
            assertEquals(case.arguments, call.second)
        }
    }

    @Test
    fun listRequestPreservesNullNumberArrayNestedDateEnumAndBooleanResponseFields() {
        val bridge = RecordingAnniversaryBridge()
        val result = invoke(
            handler(bridge),
            NativeMethodChannelHandler.MethodAnniversaryList,
            listRequest(),
        )

        val forwarded = bridge.calls.single().second
        assertEquals(listOf(CategoryId), forwarded["category_ids"])
        assertEquals(listOf("important_noturgent"), forwarded["importance"])
        @Suppress("UNCHECKED_CAST")
        val pagination = forwarded["pagination"] as Map<String, Any?>
        assertEquals(2, pagination["page"])
        assertEquals(null, pagination["cursor"])
        @Suppress("UNCHECKED_CAST")
        val responsePagination = (result.successMap()["data"] as Map<String, Any?>)["pagination"] as Map<String, Any?>
        assertEquals(false, responsePagination["has_more"])
    }

    @Test
    @Suppress("UNCHECKED_CAST")
    fun nestedSortAndDoublePositionConflictFailBeforeTheNativeBridge() {
        val nestedOnly = listRequest().toMutableMap().also { request ->
            request.remove("sort_by")
            request.remove("sort_direction")
            val pagination = (request["pagination"] as Map<String, Any?>).toMutableMap()
            pagination["sort_by"] = "title"
            request["pagination"] = pagination
        }
        val conflicting = listRequest().toMutableMap().also { request ->
            val pagination = (request["pagination"] as Map<String, Any?>).toMutableMap()
            pagination["sort_by"] = "target_occurrence_date"
            pagination["sort_direction"] = "asc"
            request["pagination"] = pagination
        }
        val bridge = RecordingAnniversaryBridge()

        listOf(nestedOnly, conflicting).forEach { invalid ->
            val result = invoke(
                handler(bridge),
                NativeMethodChannelHandler.MethodAnniversaryList,
                invalid,
            )
            assertEquals(NativeErrorCodes.ContractValidationFailed, result.errorCode())
        }
        assertTrue(bridge.calls.isEmpty())
    }

    @Test
    fun businessAndContractErrorsAreForwardedAsNativeResultWithoutPlatformError() {
        val errors = listOf(
            NativeErrorCodes.AnniversaryNotFound,
            NativeErrorCodes.ContractValidationFailed,
            NativeErrorCodes.AnniversaryCalendarUnsupported,
        )
        errors.forEach { code ->
            val bridge = RecordingAnniversaryBridge(
                overrideJson = nativeFailure(code, requestId = "failure-$code"),
            )
            val result = invoke(
                handler(bridge),
                NativeMethodChannelHandler.MethodAnniversaryDetail,
                mapOf("id" to AnniversaryId, "timezone" to "Asia/Shanghai"),
            )

            assertFalse(result.errorCalled)
            assertEquals(false, result.successMap()["ok"])
            assertEquals(code, result.errorCode())
            assertEquals("failure-$code", result.successMap()["request_id"])
        }
    }

    @Test
    fun missingRecurrenceOrTimezoneFailsBeforeTheNativeBridge() {
        val bridge = RecordingAnniversaryBridge()
        val invalidRequests = listOf(
            createRequest().toMutableMap().also { it.remove("recurrence") },
            createRequest().toMutableMap().also { it.remove("timezone") },
            createRequest().toMutableMap().also { it["timezone"] = "" },
        )

        invalidRequests.forEach { invalid ->
            val result = invoke(
                handler(bridge),
                NativeMethodChannelHandler.MethodAnniversaryCreate,
                invalid,
            )
            assertEquals(NativeErrorCodes.ContractValidationFailed, result.errorCode())
        }
        assertTrue(bridge.calls.isEmpty())
    }

    @Test
    fun impossibleDateAndUtcInstantFailAtTheContractBoundary() {
        val requestBridge = RecordingAnniversaryBridge()
        val invalidRequest = createRequest().toMutableMap().also {
            it["date"] = "2021-02-29"
        }
        val requestResult = invoke(
            handler(requestBridge),
            NativeMethodChannelHandler.MethodAnniversaryCreate,
            invalidRequest,
        )
        assertEquals(NativeErrorCodes.ContractValidationFailed, requestResult.errorCode())
        assertTrue(requestBridge.calls.isEmpty())

        val invalidAnniversary = anniversaryResponse().toMutableMap().also {
            it["created_at"] = "2026-02-30T01:02:03Z"
        }
        val invalidDetail = detailResponse().toMutableMap().also {
            it["anniversary"] = invalidAnniversary
        }
        val responseResult = invoke(
            handler(
                RecordingAnniversaryBridge(
                    overrideJson = nativeSuccess(invalidDetail, requestId = "invalid-instant"),
                ),
            ),
            NativeMethodChannelHandler.MethodAnniversaryDetail,
            mapOf("id" to AnniversaryId, "timezone" to "Asia/Shanghai"),
        )
        assertEquals(NativeErrorCodes.ContractValidationFailed, responseResult.errorCode())
    }

    @Test
    fun malformedNativeSuccessIsConvertedToContractFailure() {
        val malformed = nativeSuccess(
            linkedMapOf("anniversary" to anniversaryResponse()),
            requestId = "malformed",
        )
        val result = invoke(
            handler(RecordingAnniversaryBridge(overrideJson = malformed)),
            NativeMethodChannelHandler.MethodAnniversaryDetail,
            mapOf("id" to AnniversaryId, "timezone" to "Asia/Shanghai"),
        )

        assertEquals(NativeErrorCodes.ContractValidationFailed, result.errorCode())
    }

    private fun handler(bridge: NativeAnniversaryBridge) = NativeMethodChannelHandler(
        nativeCalendarCoreBridge = unusedAggregateBridge(),
        nativeAnniversaryBridge = bridge,
        contractProfile = NativeContractProfile.V2,
        executor = Executor { command -> command.run() },
        resultDispatcher = ResultDispatcher { block -> block() },
        logger = NativeBridgeLogger { _, _, _ -> },
    )

    private fun invoke(
        handler: NativeMethodChannelHandler,
        method: String,
        arguments: Map<String, Any?>,
    ): RecordingResult = RecordingResult().also {
        handler.onMethodCall(MethodCall(method, arguments), it)
    }

    private class RecordingAnniversaryBridge(
        private val overrideJson: String? = null,
    ) : NativeAnniversaryBridge {
        val calls = mutableListOf<Pair<String, Map<String, Any?>>>()

        override fun createAnniversary(requestJson: String) = record("create", requestJson, detailResponse())
        override fun updateAnniversary(requestJson: String) = record("update", requestJson, detailResponse())
        override fun deleteAnniversary(requestJson: String) = record("delete", requestJson, anniversaryResponse(deleted = true))
        override fun getAnniversaryDetail(requestJson: String) = record("detail", requestJson, detailResponse())
        override fun listAnniversaries(requestJson: String) = record("list", requestJson, listResponse())
        override fun previewAnniversaryCountdown(requestJson: String) = record("preview", requestJson, countdownResponse())

        private fun record(operation: String, requestJson: String, data: Any?): String {
            calls += operation to NativeContractJsonCodec.decodeObject(requestJson)
            return overrideJson ?: nativeSuccess(data, requestId = "$operation-request")
        }
    }

    private class RecordingResult : MethodChannel.Result {
        var successValue: Any? = null
            private set
        var successCalled = false
            private set
        var errorCalled = false
            private set

        override fun success(result: Any?) {
            successCalled = true
            successValue = result
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            errorCalled = true
        }

        override fun notImplemented() = Unit

        @Suppress("UNCHECKED_CAST")
        fun successMap(): Map<String, Any?> = successValue as Map<String, Any?>

        @Suppress("UNCHECKED_CAST")
        fun errorCode(): String = ((successMap()["error"] as Map<String, Any?>)["code"] as String)
    }

    private data class Case(
        val method: String,
        val arguments: Map<String, Any?>,
        val bridgeOperation: String,
    )

    companion object {
        private const val AnniversaryId = "11111111-1111-4111-8111-111111111111"
        private const val RecurrenceId = "22222222-2222-4222-8222-222222222222"
        private const val CategoryId = "33333333-3333-4333-8333-333333333333"

        private fun createRequest(): Map<String, Any?> = linkedMapOf(
            "title" to "Project anniversary",
            "date" to "2020-02-29",
            "calendar_type" to "solar",
            "category_id" to CategoryId,
            "recurrence" to linkedMapOf("frequency" to "yearly", "interval" to 1),
            "note" to null,
            "importance" to "important_noturgent",
            "timezone" to "Asia/Shanghai",
        )

        private fun updateRequest(): Map<String, Any?> = linkedMapOf(
            "id" to AnniversaryId,
            *createRequest().entries.map { it.key to it.value }.toTypedArray(),
        )

        private fun listRequest(): Map<String, Any?> = linkedMapOf(
            "timezone" to "Asia/Shanghai",
            "category_ids" to listOf(CategoryId),
            "importance" to listOf("important_noturgent"),
            "pagination" to linkedMapOf(
                "page" to 2,
                "page_size" to 20,
                "cursor" to null,
            ),
            "sort_by" to "countdown_days",
            "sort_direction" to "desc",
        )

        private fun anniversaryResponse(deleted: Boolean = false): Map<String, Any?> = linkedMapOf(
            "id" to AnniversaryId,
            "title" to "Project anniversary",
            "date" to "2020-02-29",
            "calendar_type" to "solar",
            "category_id" to CategoryId,
            "recurrence_id" to RecurrenceId,
            "note" to null,
            "importance" to "important_noturgent",
            "created_at" to "2026-08-08T01:02:03Z",
            "updated_at" to "2026-08-08T02:03:04Z",
            "deleted_at" to if (deleted) "2026-08-08T03:04:05Z" else null,
        )

        private fun countdownResponse(): Map<String, Any?> = linkedMapOf(
            "relation" to "remaining",
            "days" to 203,
            "target_occurrence_date" to "2027-02-28",
            "iso_weekday" to 7,
            "timezone" to "Asia/Shanghai",
            "calculated_at" to "2026-08-08T04:05:06Z",
        )

        private fun detailResponse(): Map<String, Any?> = linkedMapOf(
            "anniversary" to anniversaryResponse(),
            "recurrence" to linkedMapOf(
                "recurrence_id" to RecurrenceId,
                "frequency" to "yearly",
                "interval" to 1,
            ),
            "countdown" to countdownResponse(),
        )

        private fun listResponse(): Map<String, Any?> = linkedMapOf(
            "items" to listOf(
                linkedMapOf(
                    "anniversary" to anniversaryResponse(),
                    "countdown" to countdownResponse(),
                ),
            ),
            "pagination" to linkedMapOf(
                "total" to 1,
                "page" to 2,
                "page_size" to 20,
                "has_more" to false,
                "next_cursor" to null,
            ),
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

        private fun nativeFailure(code: String, requestId: String): String =
            NativeContractJsonCodec.encodeObject(
                linkedMapOf(
                    "ok" to false,
                    "data" to null,
                    "error" to linkedMapOf(
                        "code" to code,
                        "message" to "Anniversary failure",
                        "details" to linkedMapOf("source" to "test"),
                        "retryable" to false,
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
