package com.excellentcalendar.excellent_calendar.bridge

import com.excellentcalendar.excellent_calendar.bridge.channel.NativeBridgeLogger
import com.excellentcalendar.excellent_calendar.bridge.channel.NativeMethodChannelHandler
import com.excellentcalendar.excellent_calendar.bridge.channel.ResultDispatcher
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.native.NativeCalendarCoreBridge
import com.excellentcalendar.excellent_calendar.bridge.native.NativeContractProfile
import com.excellentcalendar.excellent_calendar.bridge.runtime.DeviceTimezoneProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.reflect.Proxy
import java.util.concurrent.Executor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RuntimeTimezoneMethodChannelHandlerTest {
    @Test
    fun deviceTimezoneIsReadAgainForEveryCall() {
        var timezone = "Europe/London"
        val handler = handler(
            bridge = runtimeBridge(),
            deviceTimezoneProvider = DeviceTimezoneProvider { timezone },
        )

        val first = invoke(handler, NativeMethodChannelHandler.MethodRuntimeDeviceTimezone, emptyMap<String, Any?>())
        assertEquals("Europe/London", first.data()["timezone"])

        timezone = "Asia/Shanghai"
        val second = invoke(handler, NativeMethodChannelHandler.MethodRuntimeDeviceTimezone, emptyMap<String, Any?>())
        assertEquals("Asia/Shanghai", second.data()["timezone"])
        assertEquals(2, second.successMap()["contract_version"])
    }

    @Test
    fun resolveAndBatchCallsForwardStrictJsonAndValidateNativeResponses() {
        var resolveRequest: String? = null
        var localizeRequest: String? = null
        val bridge = runtimeBridge(
            resolve = { request ->
                resolveRequest = request
                successJson(
                    mapOf(
                        "requested_local_datetime" to "2026-10-25T01:30:00",
                        "resolved_local_datetime" to "2026-10-25T01:30:00",
                        "utc_instant" to "2026-10-25T00:30:00Z",
                        "timezone" to "Europe/London",
                        "resolution" to "fold_earlier",
                    ),
                )
            },
            localize = { request ->
                localizeRequest = request
                successJson(
                    mapOf(
                        "timezone" to "Europe/London",
                        "items" to listOf(
                            mapOf(
                                "instant" to "2026-03-29T01:00:00Z",
                                "local_datetime" to "2026-03-29T02:00:00",
                            ),
                            mapOf(
                                "instant" to "2026-03-29T01:00:00Z",
                                "local_datetime" to "2026-03-29T02:00:00",
                            ),
                        ),
                    ),
                )
            },
        )
        val handler = handler(bridge)

        val resolved = invoke(
            handler,
            NativeMethodChannelHandler.MethodRuntimeResolveLocalDateTime,
            mapOf(
                "local_datetime" to "2026-10-25T01:30:00",
                "timezone" to "Europe/London",
            ),
        )
        assertEquals("fold_earlier", resolved.data()["resolution"])
        assertEquals(
            "2026-10-25T01:30:00",
            NativeContractJsonCodec.decodeObject(resolveRequest!!)["local_datetime"],
        )

        val localized = invoke(
            handler,
            NativeMethodChannelHandler.MethodRuntimeLocalizeInstants,
            mapOf(
                "timezone" to "Europe/London",
                "instants" to listOf("2026-03-29T01:00:00Z", "2026-03-29T01:00:00Z"),
            ),
        )
        @Suppress("UNCHECKED_CAST")
        val items = localized.data()["items"] as List<Map<String, Any?>>
        assertEquals(2, items.size)
        assertEquals(
            listOf("2026-03-29T01:00:00Z", "2026-03-29T01:00:00Z"),
            NativeContractJsonCodec.decodeObject(localizeRequest!!)["instants"],
        )
    }

    @Test
    fun malformedRequestAndReorderedNativeBatchFailWithoutFakeSuccess() {
        var nativeCalls = 0
        val handler = handler(
            runtimeBridge(
                localize = {
                    nativeCalls += 1
                    successJson(
                        mapOf(
                            "timezone" to "Europe/London",
                            "items" to listOf(
                                mapOf(
                                    "instant" to "2026-03-29T01:00:00Z",
                                    "local_datetime" to "2026-03-29T02:00:00",
                                ),
                                mapOf(
                                    "instant" to "2026-03-29T00:30:00Z",
                                    "local_datetime" to "2026-03-29T00:30:00",
                                ),
                            ),
                        ),
                    )
                },
            ),
        )

        val invalid = invoke(
            handler,
            NativeMethodChannelHandler.MethodRuntimeLocalizeInstants,
            mapOf("timezone" to "Europe/London", "instants" to emptyList<String>()),
        ).successMap()
        assertEquals(false, invalid["ok"])
        assertEquals(0, nativeCalls)

        val reordered = invoke(
            handler,
            NativeMethodChannelHandler.MethodRuntimeLocalizeInstants,
            mapOf(
                "timezone" to "Europe/London",
                "instants" to listOf("2026-03-29T00:30:00Z", "2026-03-29T01:00:00Z"),
            ),
        ).successMap()
        assertEquals(false, reordered["ok"])
        @Suppress("UNCHECKED_CAST")
        val error = reordered["error"] as Map<String, Any?>
        assertEquals(NativeErrorCodes.ContractValidationFailed, error["code"])
        assertEquals(1, nativeCalls)
    }

    private fun handler(
        bridge: NativeCalendarCoreBridge,
        deviceTimezoneProvider: DeviceTimezoneProvider = DeviceTimezoneProvider { "Asia/Shanghai" },
    ) = NativeMethodChannelHandler(
        nativeCalendarCoreBridge = bridge,
        contractProfile = NativeContractProfile.V2,
        executor = Executor { it.run() },
        resultDispatcher = ResultDispatcher { it() },
        logger = NativeBridgeLogger { _, _, _ -> },
        deviceTimezoneProvider = deviceTimezoneProvider,
    )

    private fun runtimeBridge(
        resolve: (String) -> String = { throw AssertionError("Unexpected resolve call") },
        localize: (String) -> String = { throw AssertionError("Unexpected localize call") },
    ): NativeCalendarCoreBridge = Proxy.newProxyInstance(
        NativeCalendarCoreBridge::class.java.classLoader,
        arrayOf(NativeCalendarCoreBridge::class.java),
    ) { _, method, arguments ->
        when (method.name) {
            "resolveLocalDateTime" -> resolve(arguments!![0] as String)
            "localizeInstants" -> localize(arguments!![0] as String)
            "toString" -> "RuntimeTimezoneFakeBridge"
            "hashCode" -> System.identityHashCode(this)
            "equals" -> false
            else -> throw AssertionError("Unexpected bridge call: ${method.name}")
        }
    } as NativeCalendarCoreBridge

    private fun successJson(data: Map<String, Any?>): String = NativeContractJsonCodec.encodeObject(
        NativeResultContract.success(data, requestId = "runtime-request", contractVersion = 2).toMap(),
    )

    private fun invoke(
        handler: NativeMethodChannelHandler,
        method: String,
        arguments: Any?,
    ): RecordingResult = RecordingResult().also {
        handler.onMethodCall(MethodCall(method, arguments), it)
    }

    private class RecordingResult : MethodChannel.Result {
        private var value: Any? = null
        private var successCalled = false
        private var errorCalled = false
        private var notImplementedCalled = false

        override fun success(result: Any?) {
            successCalled = true
            value = result
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            errorCalled = true
        }

        override fun notImplemented() {
            notImplementedCalled = true
        }

        @Suppress("UNCHECKED_CAST")
        fun successMap(): Map<String, Any?> {
            assertTrue(successCalled)
            assertFalse(errorCalled)
            assertFalse(notImplementedCalled)
            return value as Map<String, Any?>
        }

        @Suppress("UNCHECKED_CAST")
        fun data(): Map<String, Any?> = successMap()["data"] as Map<String, Any?>
    }
}
