package com.excellentcalendar.excellent_calendar.bridge.native

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class JniNativeCalendarCoreBridgeRuntimeTest {
    @Test
    fun retryableRuntimeInitializationFailureIsRetriedInSameProcess() {
        var initializationCalls = 0
        val failure = failureJson(NativeErrorCodes.StorageIoError, retryable = true)
        val bridge = bridge {
            initializationCalls += 1
            failure
        }

        assertEquals(failure, bridge.createEvent("{}"))
        assertEquals(failure, bridge.createEvent("{}"))

        assertEquals(2, initializationCalls)
    }

    @Test
    fun nonRetryableRuntimeInitializationFailureRemainsCached() {
        var initializationCalls = 0
        val failure = failureJson(NativeErrorCodes.StorageDataCorrupted, retryable = false)
        val bridge = bridge {
            initializationCalls += 1
            failure
        }

        assertEquals(failure, bridge.createEvent("{}"))
        assertEquals(failure, bridge.createEvent("{}"))

        assertEquals(1, initializationCalls)
    }

    @Test
    fun storageV4RuntimeInitializationResponseIsAccepted() {
        var initializationCalls = 0
        val bridge = bridge {
            initializationCalls += 1
            successJson(storageFormatVersion = 4)
        }

        try {
            bridge.createEvent("{}")
            fail("native event call unexpectedly resolved in the JVM test")
        } catch (error: NativeBridgeUnavailableException) {
            assertTrue(error.message.orEmpty().contains("nativeCreateEvent"))
        }
        assertEquals(1, initializationCalls)
    }

    @Test
    fun obsoleteStorageV2RuntimeInitializationResponseIsRejected() {
        val result = NativeContractJsonCodec.decodeObject(
            bridge { successJson(storageFormatVersion = 2) }.createEvent("{}"),
        )

        assertEquals(false, result["ok"])
        @Suppress("UNCHECKED_CAST")
        val error = result["error"] as Map<String, Any?>
        assertEquals(NativeErrorCodes.ContractValidationFailed, error["code"])
        @Suppress("UNCHECKED_CAST")
        val details = error["details"] as Map<String, Any?>
        assertEquals("data", details["field"])
    }

    private fun bridge(initializer: (String) -> String) = JniNativeCalendarCoreBridge(
        profile = NativeContractProfile.V2,
        runtimeRequestProvider = NativeRuntimeRequestProvider { "{}" },
        libraryLoader = NativeLibraryLoader { },
        runtimeInitializer = initializer,
    )

    private fun successJson(storageFormatVersion: Int): String = NativeContractJsonCodec.encodeObject(
        linkedMapOf(
            "ok" to true,
            "data" to linkedMapOf(
                "initialized" to true,
                "storage_format_version" to storageFormatVersion,
                "tzdb_version" to BundledTzdbExtractor.Version,
            ),
            "error" to null,
            "contract_version" to 2,
            "request_id" to "runtime-test",
        ),
    )

    private fun failureJson(code: String, retryable: Boolean): String = NativeContractJsonCodec.encodeObject(
        NativeResultContract.failure(
            code = code,
            message = "runtime initialization failed",
            retryable = retryable,
            contractVersion = 2,
        ).toMap(),
    )
}
