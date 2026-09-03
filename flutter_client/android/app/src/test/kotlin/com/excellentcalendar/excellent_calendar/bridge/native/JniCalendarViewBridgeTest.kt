package com.excellentcalendar.excellent_calendar.bridge.native

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import java.lang.reflect.Modifier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class JniCalendarViewBridgeTest {
    @Test
    fun narrowAdapterUsesExactlyTheFrozenTwoSymbolsAndPreservesUnicodeJson() {
        val observed = mutableListOf<Pair<String, String>>()
        val bridge = JniCalendarViewBridge { symbol, request ->
            observed += symbol to request
            request
        }
        val requests = listOf("{\"title\":\"日历🗓️\"}", "{\"cursor\":null}")

        assertEquals(requests[0], bridge.calendarRangeSummary(requests[0]))
        assertEquals(requests[1], bridge.calendarListDayItems(requests[1]))
        assertEquals(CalendarViewJniSymbolManifest.methods, observed.map { it.first })
        assertEquals(requests, observed.map { it.second })
    }

    @Test
    fun aggregateDeclarationsRemainNativeAndNormalizeMissingSymbols() {
        val calls = linkedMapOf<String, (JniNativeCalendarCoreBridge) -> String>(
            "nativeCalendarRangeSummaryV2" to { it.calendarRangeSummary("{}") },
            "nativeCalendarListDayItemsV2" to { it.calendarListDayItems("{}") },
        )

        calls.forEach { (symbol, call) ->
            val declaration = JniNativeCalendarCoreBridge::class.java.getDeclaredMethod(symbol, String::class.java)
            assertTrue("$symbol must remain a native declaration", Modifier.isNative(declaration.modifiers))
            try {
                call(unloadedBridge())
                fail("$symbol unexpectedly resolved without the native library")
            } catch (error: NativeBridgeUnavailableException) {
                assertEquals("JNI symbol $symbol is unavailable.", error.message)
                assertTrue(error.cause is UnsatisfiedLinkError)
            }
        }
    }

    @Test
    fun runtimeFailureIsReturnedBeforeEitherCalendarSymbolIsInvoked() {
        val runtimeFailure = NativeContractJsonCodec.encodeObject(
            linkedMapOf(
                "ok" to false,
                "data" to null,
                "error" to linkedMapOf(
                    "code" to NativeErrorCodes.StorageNotInitialized,
                    "message" to "runtime unavailable",
                    "details" to null,
                    "retryable" to false,
                ),
                "contract_version" to 2,
                "request_id" to "runtime-failure",
            ),
        )
        val bridge = JniNativeCalendarCoreBridge(
            profile = NativeContractProfile.V2,
            runtimeRequestProvider = NativeRuntimeRequestProvider { "{}" },
            libraryLoader = NativeLibraryLoader { },
            runtimeInitializer = { runtimeFailure },
        )

        listOf(bridge.calendarRangeSummary("{}"), bridge.calendarListDayItems("{}")).forEach { json ->
            val result = NativeContractJsonCodec.decodeObject(json)
            @Suppress("UNCHECKED_CAST")
            val error = result["error"] as Map<String, Any?>
            assertEquals(false, result["ok"])
            assertEquals(NativeErrorCodes.StorageNotInitialized, error["code"])
            assertEquals("runtime-failure", result["request_id"])
        }
    }

    private fun unloadedBridge() = JniNativeCalendarCoreBridge(
        profile = NativeContractProfile.V2,
        runtimeRequestProvider = NativeRuntimeRequestProvider { "{}" },
        libraryLoader = NativeLibraryLoader { },
        runtimeInitializer = {
            NativeContractJsonCodec.encodeObject(
                linkedMapOf(
                    "ok" to true,
                    "data" to linkedMapOf(
                        "initialized" to true,
                        "storage_format_version" to 5,
                        "tzdb_version" to BundledTzdbExtractor.Version,
                    ),
                    "error" to null,
                    "contract_version" to 2,
                    "request_id" to "calendar-runtime-test",
                ),
            )
        },
    )
}
