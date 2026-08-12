package com.excellentcalendar.excellent_calendar.bridge

import com.excellentcalendar.excellent_calendar.bridge.channel.NativeBridgeLogger
import com.excellentcalendar.excellent_calendar.bridge.channel.NativeMethodChannelHandler
import com.excellentcalendar.excellent_calendar.bridge.channel.ResultDispatcher
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.EventV2Contracts
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeContractViolation
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.native.NativeCalendarCoreBridge
import com.excellentcalendar.excellent_calendar.bridge.native.NativeContractProfile
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.reflect.Proxy
import java.util.concurrent.Executor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class EventCategoryBoundaryTest {
    @Test
    fun malformedCategoryRequestFieldsFailOnceBeforeNativeExecution() {
        val cases = listOf(
            NativeMethodChannelHandler.MethodEventCreate to timedCreate(categoryId = 7),
            NativeMethodChannelHandler.MethodEventUpdate to linkedMapOf(
                "id" to EventId,
                "category_id" to 7,
            ),
            NativeMethodChannelHandler.MethodEventSearch to linkedMapOf(
                "category_ids" to listOf(CategoryId, 7),
            ),
            NativeMethodChannelHandler.MethodEventSearch to linkedMapOf(
                "category_ids" to null,
            ),
        )

        cases.forEach { (method, arguments) ->
            val native = RecordingNativeBridge { operation, _ ->
                throw AssertionError("$operation must not run for an invalid request")
            }
            val result = invoke(handler(native.bridge), method, arguments)

            assertContractFailure(result)
            assertTrue(native.calls.isEmpty())
        }
    }

    @Test
    fun updatePreservesOmittedNullAndStringCategoryIdSemantics() {
        val omitted = EventV2Contracts.update(linkedMapOf("id" to EventId)).value
        val cleared = EventV2Contracts.update(
            linkedMapOf("id" to EventId, "category_id" to null),
        ).value
        val replaced = EventV2Contracts.update(
            linkedMapOf("id" to EventId, "category_id" to CategoryId),
        ).value

        assertFalse(omitted.containsKey("category_id"))
        assertTrue(cleared.containsKey("category_id"))
        assertNull(cleared["category_id"])
        assertEquals(CategoryId, replaced["category_id"])
        EventV2Contracts.search(linkedMapOf("category_ids" to listOf(CategoryId, "legacy-category")))
    }

    @Test
    fun malformedNativeCategoryFieldsBecomeOneContractFailure() {
        val invalidCreate = RecordingNativeBridge { operation, _ ->
            assertEquals("createEvent", operation)
            nativeSuccess(eventResponse(categoryId = 7))
        }
        val createResult = invoke(
            handler(invalidCreate.bridge),
            NativeMethodChannelHandler.MethodEventCreate,
            timedCreate(categoryId = CategoryId),
        )

        assertContractFailure(createResult)
        assertEquals(listOf("createEvent"), invalidCreate.calls.map { it.first })

        val invalidDetail = RecordingNativeBridge { operation, _ ->
            assertEquals("getEventDetail", operation)
            nativeSuccess(eventDetail(categoryId = CategoryId, category = "not-a-category-object"))
        }
        val detailResult = invoke(
            handler(invalidDetail.bridge),
            NativeMethodChannelHandler.MethodEventDetail,
            linkedMapOf("id" to EventId),
        )

        assertContractFailure(detailResult)
        assertEquals(listOf("getEventDetail"), invalidDetail.calls.map { it.first })
    }

    @Test
    fun eventDetailAcceptsTheThreeDeclaredCategoryStates() {
        EventV2Contracts.detailResponse(eventDetail(categoryId = null, category = null))
        EventV2Contracts.detailResponse(
            eventDetail(categoryId = CategoryId, category = categoryResponse()),
        )
        EventV2Contracts.detailResponse(
            eventDetail(categoryId = "legacy-missing-category", category = null),
        )
    }

    @Test
    fun eventDetailRejectsUnclassifiedMismatchedAndDeletedCategoryProjections() {
        val invalidDetails = listOf(
            eventDetail(categoryId = null, category = categoryResponse()),
            eventDetail(
                categoryId = CategoryId,
                category = categoryResponse(id = OtherCategoryId),
            ),
            eventDetail(
                categoryId = CategoryId,
                category = categoryResponse(deletedAt = "2026-08-11T10:00:00Z"),
            ),
        )

        invalidDetails.forEach { detail ->
            assertThrows(NativeContractViolation::class.java) {
                EventV2Contracts.detailResponse(detail)
            }
        }
    }

    private fun handler(bridge: NativeCalendarCoreBridge) = NativeMethodChannelHandler(
        nativeCalendarCoreBridge = bridge,
        contractProfile = NativeContractProfile.V2,
        executor = Executor { command -> command.run() },
        resultDispatcher = ResultDispatcher { block -> block() },
        logger = NativeBridgeLogger { _, _, _ -> },
    )

    private fun invoke(
        handler: NativeMethodChannelHandler,
        method: String,
        arguments: Map<String, Any?>,
    ): RecordingResult = RecordingResult().also { result ->
        handler.onMethodCall(MethodCall(method, arguments), result)
    }

    private fun assertContractFailure(result: RecordingResult) {
        val returned = result.successMap()
        assertEquals(false, returned["ok"])
        assertNull(returned["data"])
        @Suppress("UNCHECKED_CAST")
        val error = returned["error"] as Map<String, Any?>
        assertEquals(NativeErrorCodes.ContractValidationFailed, error["code"])
        assertEquals(1, result.successCount)
        assertEquals(0, result.errorCount)
        assertEquals(0, result.notImplementedCount)
    }

    private class RecordingNativeBridge(
        private val responder: (operation: String, requestJson: String) -> String,
    ) {
        val calls = mutableListOf<Pair<String, Map<String, Any?>>>()

        val bridge: NativeCalendarCoreBridge = Proxy.newProxyInstance(
            NativeCalendarCoreBridge::class.java.classLoader,
            arrayOf(NativeCalendarCoreBridge::class.java),
        ) { proxy, method, arguments ->
            when (method.name) {
                "toString" -> "RecordingNativeCalendarCoreBridge"
                "hashCode" -> System.identityHashCode(proxy)
                "equals" -> proxy === arguments?.firstOrNull()
                else -> {
                    val requestJson = arguments?.singleOrNull() as? String
                        ?: throw AssertionError("Unexpected ${method.name} arguments")
                    calls += method.name to NativeContractJsonCodec.decodeObject(requestJson)
                    responder(method.name, requestJson)
                }
            }
        } as NativeCalendarCoreBridge
    }

    private class RecordingResult : MethodChannel.Result {
        private var successValue: Any? = null
        var successCount = 0
            private set
        var errorCount = 0
            private set
        var notImplementedCount = 0
            private set

        override fun success(result: Any?) {
            successCount += 1
            successValue = result
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            errorCount += 1
        }

        override fun notImplemented() {
            notImplementedCount += 1
        }

        @Suppress("UNCHECKED_CAST")
        fun successMap(): Map<String, Any?> = successValue as Map<String, Any?>
    }

    private companion object {
        const val EventId = "10000000-0000-4000-8000-000000000001"
        const val CategoryId = "40000000-0000-4000-8000-000000000001"
        const val OtherCategoryId = "40000000-0000-4000-8000-000000000002"

        fun timedCreate(categoryId: Any?): Map<String, Any?> = linkedMapOf(
            "title" to "Category boundary",
            "start_at" to "2026-08-11T08:00:00Z",
            "end_at" to "2026-08-11T09:00:00Z",
            "start_date" to null,
            "end_date" to null,
            "is_all_day" to false,
            "category_id" to categoryId,
            "timezone" to "Asia/Shanghai",
            "source" to "manual",
        )

        fun eventResponse(categoryId: Any?): Map<String, Any?> = linkedMapOf(
            "id" to EventId,
            "title" to "Category boundary",
            "content" to null,
            "start_at" to "2026-08-11T08:00:00Z",
            "end_at" to "2026-08-11T09:00:00Z",
            "start_date" to null,
            "end_date" to null,
            "is_all_day" to false,
            "has_recurrence" to false,
            "status" to "active",
            "completed_at" to null,
            "recurrence_id" to null,
            "recurrence_revision" to null,
            "category_id" to categoryId,
            "importance" to null,
            "location" to null,
            "timezone" to "Asia/Shanghai",
            "source" to "manual",
            "created_at" to "2026-08-11T07:00:00Z",
            "updated_at" to "2026-08-11T07:00:00Z",
            "deleted_at" to null,
        )

        fun eventDetail(categoryId: Any?, category: Any?): Map<String, Any?> = linkedMapOf(
            "event" to eventResponse(categoryId),
            "recurrence" to null,
            "reminders" to emptyList<Any?>(),
            "category" to category,
        )

        fun categoryResponse(
            id: String = CategoryId,
            deletedAt: String? = null,
        ): Map<String, Any?> = linkedMapOf(
            "id" to id,
            "name" to "工作",
            "description" to null,
            "color" to "#39AFBD",
            "icon" to null,
            "sort_order" to 1L,
            "created_at" to "2026-08-11T07:00:00Z",
            "updated_at" to "2026-08-11T07:00:00Z",
            "deleted_at" to deletedAt,
        )

        fun nativeSuccess(data: Any?): String = NativeContractJsonCodec.encodeObject(
            linkedMapOf(
                "ok" to true,
                "data" to data,
                "error" to null,
                "contract_version" to 2,
                "request_id" to "event-category-test",
            ),
        )
    }
}
