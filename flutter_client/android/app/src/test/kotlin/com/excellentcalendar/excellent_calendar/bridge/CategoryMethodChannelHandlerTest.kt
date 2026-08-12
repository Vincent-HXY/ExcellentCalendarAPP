package com.excellentcalendar.excellent_calendar.bridge

import com.excellentcalendar.excellent_calendar.bridge.channel.NativeBridgeLogger
import com.excellentcalendar.excellent_calendar.bridge.channel.NativeMethodChannelHandler
import com.excellentcalendar.excellent_calendar.bridge.channel.ResultDispatcher
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.native.JniNativeCalendarCoreBridge
import com.excellentcalendar.excellent_calendar.bridge.native.BundledTzdbExtractor
import com.excellentcalendar.excellent_calendar.bridge.native.NativeCalendarCoreBridge
import com.excellentcalendar.excellent_calendar.bridge.native.NativeCategoryBridge
import com.excellentcalendar.excellent_calendar.bridge.native.NativeContractProfile
import com.excellentcalendar.excellent_calendar.bridge.native.NativeLibraryLoader
import com.excellentcalendar.excellent_calendar.bridge.native.NativeRuntimeRequestProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.reflect.Proxy
import java.util.concurrent.Executor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CategoryMethodChannelHandlerTest {
    @Test
    fun listAndCreateRouteThroughTheNarrowBridgeWithExactJson() {
        val bridge = RecordingCategoryBridge()
        val handler = handler(bridge)

        val listResult = invoke(handler, NativeMethodChannelHandler.MethodCategoryList, emptyMap<String, Any?>())
        val createResult = invoke(handler, NativeMethodChannelHandler.MethodCategoryCreate, createRequest())

        assertEquals(listOf("list", "create"), bridge.calls.map { it.first })
        assertEquals(emptyMap<String, Any?>(), bridge.calls[0].second)
        assertEquals(createRequest(), bridge.calls[1].second)
        assertEquals(true, listResult.successMap()["ok"])
        assertEquals(true, createResult.successMap()["ok"])
        assertEquals(1, listResult.successCount)
        assertEquals(1, createResult.successCount)
        assertFalse(listResult.errorCalled)
        assertFalse(createResult.errorCalled)
        assertEquals(0, listResult.notImplementedCount)
        assertEquals(0, createResult.notImplementedCount)
    }

    @Test
    fun missingNullableFieldAndMalformedColorFailBeforeTheBridge() {
        val bridge = RecordingCategoryBridge()
        val missing = createRequest().toMutableMap().also { it.remove("description") }
        val badColor = createRequest().toMutableMap().also { it["color"] = "blue" }

        listOf(missing, badColor).forEach { request ->
            val result = invoke(
                handler(bridge),
                NativeMethodChannelHandler.MethodCategoryCreate,
                request,
            )
            assertEquals(NativeErrorCodes.ContractValidationFailed, result.errorCode())
            assertEquals(1, result.successCount)
        }
        assertTrue(bridge.calls.isEmpty())
    }

    @Test
    fun declaredNativeErrorsAndEnvelopeMetadataPassThroughUnchanged() {
        val errorCodes = listOf(
            NativeErrorCodes.ContractVersionUnsupported,
            NativeErrorCodes.CategoryNameEmpty,
            NativeErrorCodes.CategoryNotFound,
            NativeErrorCodes.FeatureNotImplemented,
        )

        errorCodes.forEach { code ->
            val response = nativeFailure(code, retryable = false)
            val result = invoke(
                handler(RecordingCategoryBridge(overrideJson = response)),
                NativeMethodChannelHandler.MethodCategoryCreate,
                createRequest(),
            )
            val returned = result.successMap()

            assertEquals(false, returned["ok"])
            assertNull(returned["data"])
            assertEquals(2, returned["contract_version"])
            assertEquals("category-error", returned["request_id"])
            @Suppress("UNCHECKED_CAST")
            val error = returned["error"] as Map<String, Any?>
            assertEquals(code, error["code"])
            assertEquals(false, error["retryable"])
            assertEquals(mapOf("source" to "category-test"), error["details"])
            assertEquals(1, result.successCount)
            assertFalse(result.errorCalled)
        }
    }

    @Test
    fun unexpectedBridgeFailureBecomesOneNormalizedNativeInternalError() {
        val bridge = object : NativeCategoryBridge {
            override fun listCategories(requestJson: String): String =
                throw IllegalStateException("sensitive native detail")

            override fun createCategory(requestJson: String): String =
                throw AssertionError("Unexpected create")
        }

        val result = invoke(
            handler(bridge),
            NativeMethodChannelHandler.MethodCategoryList,
            emptyMap<String, Any?>(),
        )
        val returned = result.successMap()

        assertEquals(NativeErrorCodes.NativeInternalError, result.errorCode())
        assertEquals(1, result.successCount)
        assertFalse(result.errorCalled)
        @Suppress("UNCHECKED_CAST")
        val details = (returned["error"] as Map<String, Any?>)["details"] as Map<String, Any?>
        assertEquals("IllegalStateException", details["reason"])
        assertFalse(details.values.any { it.toString().contains("sensitive native detail") })
    }

    @Test
    fun missingJniSymbolBecomesOneSanitizedNativeInternalError() {
        val bridge = object : NativeCategoryBridge {
            override fun listCategories(requestJson: String): String =
                throw UnsatisfiedLinkError("sensitive missing symbol name")

            override fun createCategory(requestJson: String): String =
                throw AssertionError("Unexpected create")
        }

        val result = invoke(
            handler(bridge),
            NativeMethodChannelHandler.MethodCategoryList,
            emptyMap<String, Any?>(),
        )
        val returned = result.successMap()

        assertEquals(NativeErrorCodes.NativeInternalError, result.errorCode())
        assertEquals(1, result.successCount)
        assertFalse(result.errorCalled)
        @Suppress("UNCHECKED_CAST")
        val details = (returned["error"] as Map<String, Any?>)["details"] as Map<String, Any?>
        assertEquals("UnsatisfiedLinkError", details["reason"])
        assertFalse(details.values.any { it.toString().contains("sensitive missing symbol name") })
    }

    @Test
    fun deletedOrUnsortedListResponseBecomesContractFailure() {
        val deleted = categoryResponse().toMutableMap().also {
            it["deleted_at"] = "2026-08-10T09:00:00Z"
        }
        val outOfOrder = listOf(
            categoryResponse(id = SecondCategoryId, sortOrder = 2),
            categoryResponse(id = CategoryId, sortOrder = 1),
        )
        val responses = listOf(
            nativeSuccess(linkedMapOf("items" to listOf(deleted))),
            nativeSuccess(linkedMapOf("items" to outOfOrder)),
        )

        responses.forEach { response ->
            val result = invoke(
                handler(RecordingCategoryBridge(overrideJson = response)),
                NativeMethodChannelHandler.MethodCategoryList,
                emptyMap<String, Any?>(),
            )
            assertEquals(NativeErrorCodes.ContractValidationFailed, result.errorCode())
        }
    }

    @Test
    fun productionV2BridgeUsesCategoryJniCallPointsInsteadOfFeaturePlaceholder() {
        var loadAttempts = 0
        val bridge = JniNativeCalendarCoreBridge(
            profile = NativeContractProfile.V2,
            runtimeRequestProvider = NativeRuntimeRequestProvider { "{}" },
            libraryLoader = NativeLibraryLoader {
                loadAttempts += 1
            },
            runtimeInitializer = {
                NativeContractJsonCodec.encodeObject(
                    linkedMapOf(
                        "ok" to true,
                        "data" to linkedMapOf(
                            "initialized" to true,
                            "storage_format_version" to 2,
                            "tzdb_version" to BundledTzdbExtractor.Version,
                        ),
                        "error" to null,
                        "contract_version" to 2,
                        "request_id" to "category-runtime-test",
                    ),
                )
            },
        )

        listOf(
            invoke(
                handler(bridge),
                NativeMethodChannelHandler.MethodCategoryList,
                emptyMap<String, Any?>(),
            ),
            invoke(
                handler(bridge),
                NativeMethodChannelHandler.MethodCategoryCreate,
                createRequest(),
            ),
        ).forEach { completion ->
            val result = completion.successMap()
            assertEquals(false, result["ok"])
            @Suppress("UNCHECKED_CAST")
            val error = result["error"] as Map<String, Any?>
            assertEquals(NativeErrorCodes.NativeInternalError, error["code"])
            assertEquals(false, error["retryable"])
            assertEquals(2, result["contract_version"])
            assertEquals(1, completion.successCount)
            assertFalse(completion.errorCalled)
        }
        assertEquals(1, loadAttempts)
    }

    @Test
    fun unknownMethodUsesTheExistingNotImplementedPathExactlyOnce() {
        val result = invoke(handler(RecordingCategoryBridge()), "category.unknown", emptyMap<String, Any?>())

        assertEquals(0, result.successCount)
        assertFalse(result.errorCalled)
        assertEquals(1, result.notImplementedCount)
    }

    @Test
    fun executorRejectionCompletesExactlyOnceWithoutCallingTheBridge() {
        val bridge = RecordingCategoryBridge()
        val handler = handler(
            bridge,
            executor = Executor { throw IllegalStateException("executor rejected") },
        )

        val result = invoke(
            handler,
            NativeMethodChannelHandler.MethodCategoryList,
            emptyMap<String, Any?>(),
        )

        assertEquals(NativeErrorCodes.NativeInternalError, result.errorCode())
        assertEquals(1, result.successCount)
        assertTrue(bridge.calls.isEmpty())
    }

    private fun handler(
        bridge: NativeCategoryBridge,
        executor: Executor = Executor { command -> command.run() },
    ) = NativeMethodChannelHandler(
        nativeCalendarCoreBridge = unusedAggregateBridge(),
        nativeCategoryBridge = bridge,
        contractProfile = NativeContractProfile.V2,
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
    }

    private class RecordingCategoryBridge(
        private val overrideJson: String? = null,
    ) : NativeCategoryBridge {
        val calls = mutableListOf<Pair<String, Map<String, Any?>>>()

        override fun listCategories(requestJson: String): String =
            record("list", requestJson, linkedMapOf("items" to listOf(categoryResponse())))

        override fun createCategory(requestJson: String): String =
            record("create", requestJson, categoryResponse())

        private fun record(operation: String, requestJson: String, data: Any?): String {
            calls += operation to NativeContractJsonCodec.decodeObject(requestJson)
            return overrideJson ?: nativeSuccess(data)
        }
    }

    private class RecordingResult : MethodChannel.Result {
        private var successValue: Any? = null
        var successCount = 0
            private set
        var errorCalled = false
            private set
        var notImplementedCount = 0
            private set

        override fun success(result: Any?) {
            successCount += 1
            successValue = result
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            errorCalled = true
        }

        override fun notImplemented() {
            notImplementedCount += 1
        }

        @Suppress("UNCHECKED_CAST")
        fun successMap(): Map<String, Any?> = successValue as Map<String, Any?>

        @Suppress("UNCHECKED_CAST")
        fun errorCode(): String = ((successMap()["error"] as Map<String, Any?>)["code"] as String)
    }

    companion object {
        private const val CategoryId = "40000000-0000-4000-8000-000000000001"
        private const val SecondCategoryId = "40000000-0000-4000-8000-000000000002"

        private fun createRequest(): Map<String, Any?> = linkedMapOf(
            "name" to "工作",
            "description" to "工作计划",
            "color" to "#39AFBD",
            "icon" to null,
            "sort_order" to null,
        )

        private fun categoryResponse(
            id: String = CategoryId,
            sortOrder: Int = 1,
        ): Map<String, Any?> = linkedMapOf(
            "id" to id,
            "name" to "工作",
            "description" to "工作计划",
            "color" to "#39AFBD",
            "icon" to null,
            "sort_order" to sortOrder,
            "created_at" to "2026-08-10T08:00:00Z",
            "updated_at" to "2026-08-10T08:00:00Z",
            "deleted_at" to null,
        )

        private fun nativeSuccess(data: Any?): String = NativeContractJsonCodec.encodeObject(
            linkedMapOf(
                "ok" to true,
                "data" to data,
                "error" to null,
                "contract_version" to 2,
                "request_id" to "category-test",
            ),
        )

        private fun nativeFailure(code: String, retryable: Boolean): String =
            NativeContractJsonCodec.encodeObject(
                linkedMapOf(
                    "ok" to false,
                    "data" to null,
                    "error" to linkedMapOf(
                        "code" to code,
                        "message" to "Category native failure.",
                        "details" to linkedMapOf("source" to "category-test"),
                        "retryable" to retryable,
                    ),
                    "contract_version" to 2,
                    "request_id" to "category-error",
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
