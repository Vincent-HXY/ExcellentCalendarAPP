package com.excellentcalendar.excellent_calendar.bridge.native

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import java.lang.reflect.Modifier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class JniSearchBridgeTest {
    @Test
    fun narrowAdapterUsesOnlyTheFrozenQuerySymbolAndPreservesUnicodeJson() {
        val observed = mutableListOf<Pair<String, String>>()
        val bridge = JniSearchBridge { symbol, request ->
            observed += symbol to request
            request
        }
        val request = "{\"keyword\":\"中文 😀 é 𠀋\"}"

        assertEquals(request, bridge.querySearch(request))
        assertEquals(SearchJniSymbolManifest.methods, observed.map { it.first })
        assertEquals(listOf(request), observed.map { it.second })
        assertTrue(SearchJniSymbolManifest.methods.none { it.contains("History", ignoreCase = true) })
    }

    @Test
    fun aggregateDeclarationIsNativeAndMissingSymbolIsNormalized() {
        val declaration = JniNativeCalendarCoreBridge::class.java.getDeclaredMethod(
            SearchJniSymbolManifest.methods.single(),
            String::class.java,
        )
        assertTrue(Modifier.isNative(declaration.modifiers))
        try {
            unloadedBridge().querySearch("{}")
            fail("Search symbol unexpectedly resolved without the native library")
        } catch (error: NativeBridgeUnavailableException) {
            assertEquals("JNI symbol nativeQuerySearchV2 is unavailable.", error.message)
            assertTrue(error.cause is UnsatisfiedLinkError)
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
                    "request_id" to "search-runtime-test",
                ),
            )
        },
    )
}
