package com.excellentcalendar.excellent_calendar.bridge.native

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import org.junit.Assert.assertEquals
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

    private fun bridge(initializer: (String) -> String) = JniNativeCalendarCoreBridge(
        profile = NativeContractProfile.V2,
        runtimeRequestProvider = NativeRuntimeRequestProvider { "{}" },
        libraryLoader = NativeLibraryLoader { },
        runtimeInitializer = initializer,
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
