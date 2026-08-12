package com.excellentcalendar.excellent_calendar.bridge.native

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import java.lang.reflect.Modifier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class JniNativeCalendarCoreBridgeAnniversaryTest {
    @Test
    fun everyAnniversaryBridgeMethodReachesItsDeclaredExternalJniCallPoint() {
        val calls = linkedMapOf<String, (JniNativeCalendarCoreBridge) -> String>(
            "nativeCreateAnniversaryV2" to { it.createAnniversary("{}") },
            "nativeUpdateAnniversaryV2" to { it.updateAnniversary("{}") },
            "nativeDeleteAnniversaryV2" to { it.deleteAnniversary("{}") },
            "nativeGetAnniversaryDetailV2" to { it.getAnniversaryDetail("{}") },
            "nativeListAnniversariesV2" to { it.listAnniversaries("{}") },
            "nativePreviewAnniversaryCountdownV2" to { it.previewAnniversaryCountdown("{}") },
        )

        calls.forEach { (symbol, call) ->
            val declaration = JniNativeCalendarCoreBridge::class.java.getDeclaredMethod(symbol, String::class.java)
            assertTrue("$symbol must remain a native declaration", Modifier.isNative(declaration.modifiers))
            try {
                call(bridge())
                fail("$symbol unexpectedly resolved without a C++ JNI export")
            } catch (error: NativeBridgeUnavailableException) {
                assertEquals("JNI symbol $symbol is unavailable.", error.message)
                assertTrue(error.cause is UnsatisfiedLinkError)
            }
        }
    }

    private fun bridge() = JniNativeCalendarCoreBridge(
        profile = NativeContractProfile.V2,
        runtimeRequestProvider = NativeRuntimeRequestProvider { "{}" },
        libraryLoader = NativeLibraryLoader { },
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
                    "request_id" to "runtime-test",
                ),
            )
        },
    )
}
