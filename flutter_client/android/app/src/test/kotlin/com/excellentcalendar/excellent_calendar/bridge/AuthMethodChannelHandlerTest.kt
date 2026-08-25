package com.excellentcalendar.excellent_calendar.bridge

import com.excellentcalendar.excellent_calendar.bridge.auth.RefreshTokenRecordCorruptedException
import com.excellentcalendar.excellent_calendar.bridge.auth.RefreshTokenSecureStorageException
import com.excellentcalendar.excellent_calendar.bridge.auth.RefreshTokenSecureStore
import com.excellentcalendar.excellent_calendar.bridge.auth.SecureRefreshTokenRecord
import com.excellentcalendar.excellent_calendar.bridge.channel.NativeBridgeLogger
import com.excellentcalendar.excellent_calendar.bridge.channel.NativeMethodChannelHandler
import com.excellentcalendar.excellent_calendar.bridge.channel.ResultDispatcher
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
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

class AuthMethodChannelHandlerTest {
    @Test
    fun storeThenReadRoundTripsThroughTheChannel() {
        val store = FakeStore()
        val handler = handler(store)

        val stored = invoke(
            handler,
            NativeMethodChannelHandler.MethodAuthRefreshTokenStore,
            mapOf(
                "refresh_token" to "opaque-refresh-token-value-at-least-32-characters",
                "session_id" to "62732653-c76a-40e7-bf72-bccabb54f06a",
                "expires_at" to "2026-08-31T01:00:00Z",
            ),
        ).successMap()
        assertEquals(true, stored["ok"])
        assertEquals(2, stored["contract_version"])
        @Suppress("UNCHECKED_CAST")
        val storedData = stored["data"] as Map<String, Any?>
        assertEquals(true, storedData["performed"])

        val read = invoke(handler, NativeMethodChannelHandler.MethodAuthRefreshTokenRead, emptyMap<String, Any?>())
        @Suppress("UNCHECKED_CAST")
        val readData = read.data()
        assertEquals("opaque-refresh-token-value-at-least-32-characters", readData["refresh_token"])
        assertEquals("62732653-c76a-40e7-bf72-bccabb54f06a", readData["session_id"])
        assertEquals("2026-08-31T01:00:00Z", readData["expires_at"])
    }

    @Test
    fun readWithoutStoredTokenReturnsSecureTokenNotFound() {
        val result = invoke(
            handler(FakeStore()),
            NativeMethodChannelHandler.MethodAuthRefreshTokenRead,
            emptyMap<String, Any?>(),
        ).successMap()
        assertEquals(false, result["ok"])
        assertEquals(NativeErrorCodes.SecureTokenNotFound, errorCode(result))
    }

    @Test
    fun failureEnvelopeIsAlwaysOkFalseWithNullData() {
        val result = invoke(
            handler(FakeStore()),
            NativeMethodChannelHandler.MethodAuthRefreshTokenRead,
            emptyMap<String, Any?>(),
        ).successMap()
        assertEquals(false, result["ok"])
        assertEquals(null, result["data"])
        @Suppress("UNCHECKED_CAST")
        val error = result["error"] as Map<String, Any?>
        assertTrue((error["code"] as String).isNotBlank())
        assertTrue((error["message"] as String).isNotBlank())
        assertEquals(2, result["contract_version"])
    }

    @Test
    fun deleteAndExistsReflectTheStore() {
        val store = FakeStore()
        store.record = record()
        val handler = handler(store)

        assertTrue(exists(handler))
        val deleted = invoke(
            handler,
            NativeMethodChannelHandler.MethodAuthRefreshTokenDelete,
            emptyMap<String, Any?>(),
        ).successMap()
        assertEquals(true, deleted["ok"])
        assertFalse(exists(handler))
    }

    @Test
    fun malformedStoreRequestFailsWithoutTouchingTheStore() {
        val store = FakeStore()
        val result = invoke(
            handler(store),
            NativeMethodChannelHandler.MethodAuthRefreshTokenStore,
            mapOf("refresh_token" to "short"),
        ).successMap()
        assertEquals(false, result["ok"])
        assertEquals(NativeErrorCodes.ContractValidationFailed, errorCode(result))
        assertFalse(store.exists())
    }

    @Test
    fun nonEmptyArgumentsOnReadAreRejected() {
        val result = invoke(
            handler(FakeStore()),
            NativeMethodChannelHandler.MethodAuthRefreshTokenRead,
            mapOf("unexpected" to true),
        ).successMap()
        assertEquals(false, result["ok"])
        assertEquals(NativeErrorCodes.ContractValidationFailed, errorCode(result))
    }

    @Test
    fun corruptedRecordMapsToSecureTokenCorrupted() {
        val store = FakeStore().apply { corrupt = true }
        val result = invoke(
            handler(store),
            NativeMethodChannelHandler.MethodAuthRefreshTokenRead,
            emptyMap<String, Any?>(),
        ).successMap()
        assertEquals(false, result["ok"])
        assertEquals(NativeErrorCodes.SecureTokenCorrupted, errorCode(result))
    }

    @Test
    fun sensitivePayloadIsNeverLoggedOnStoreOrRead() {
        val logged = mutableListOf<String>()
        val store = FakeStore()
        val handler = NativeMethodChannelHandler(
            nativeCalendarCoreBridge = proxyBridge(),
            contractProfile = NativeContractProfile.V2,
            authTokenStore = store,
            executor = Executor { it.run() },
            resultDispatcher = ResultDispatcher { it() },
            logger = NativeBridgeLogger { _, _, message -> logged.add(message) },
        )
        val token = "opaque-refresh-token-value-at-least-32-characters"

        invoke(
            handler,
            NativeMethodChannelHandler.MethodAuthRefreshTokenStore,
            mapOf(
                "refresh_token" to token,
                "session_id" to "62732653-c76a-40e7-bf72-bccabb54f06a",
                "expires_at" to "2026-08-31T01:00:00Z",
            ),
        ).successMap()
        invoke(handler, NativeMethodChannelHandler.MethodAuthRefreshTokenRead, emptyMap<String, Any?>())
            .successMap()

        val combined = logged.joinToString(" ")
        assertFalse("logger must not leak the token", combined.contains(token))
        assertFalse("logger must not leak the session id", combined.contains("62732653-c76a-40e7-bf72-bccabb54f06a"))
    }

    @Test
    fun storageFailureMapsToSecureTokenStorageFailedAndRetryable() {
        val store = FakeStore().apply { failStore = true }
        val result = invoke(
            handler(store),
            NativeMethodChannelHandler.MethodAuthRefreshTokenStore,
            mapOf(
                "refresh_token" to "opaque-refresh-token-value-at-least-32-characters",
                "session_id" to "62732653-c76a-40e7-bf72-bccabb54f06a",
                "expires_at" to "2026-08-31T01:00:00Z",
            ),
        ).successMap()
        assertEquals(false, result["ok"])
        @Suppress("UNCHECKED_CAST")
        val error = result["error"] as Map<String, Any?>
        assertEquals(NativeErrorCodes.SecureTokenStorageFailed, error["code"])
        assertEquals(true, error["retryable"])
    }

    private fun exists(handler: NativeMethodChannelHandler): Boolean {
        val result = invoke(
            handler,
            NativeMethodChannelHandler.MethodAuthRefreshTokenExists,
            emptyMap<String, Any?>(),
        )
        @Suppress("UNCHECKED_CAST")
        return result.data()["exists"] as Boolean
    }

    private fun errorCode(map: Map<String, Any?>): String {
        @Suppress("UNCHECKED_CAST")
        val error = map["error"] as Map<String, Any?>
        return error["code"] as String
    }

    private fun handler(store: RefreshTokenSecureStore) = NativeMethodChannelHandler(
        nativeCalendarCoreBridge = proxyBridge(),
        contractProfile = NativeContractProfile.V2,
        authTokenStore = store,
        executor = Executor { it.run() },
        resultDispatcher = ResultDispatcher { it() },
        logger = NativeBridgeLogger { _, _, _ -> },
    )

    private fun record() = SecureRefreshTokenRecord(
        refreshToken = "opaque-refresh-token-value-at-least-32-characters",
        sessionId = "62732653-c76a-40e7-bf72-bccabb54f06a",
        expiresAt = "2026-08-31T01:00:00Z",
    )

    private class FakeStore : RefreshTokenSecureStore {
        var record: SecureRefreshTokenRecord? = null
        var corrupt = false
        var failStore = false

        override fun store(record: SecureRefreshTokenRecord) {
            if (failStore) throw RefreshTokenSecureStorageException(IllegalStateException("keystore unavailable"))
            this.record = record
        }

        override fun read(): SecureRefreshTokenRecord? {
            if (corrupt) throw RefreshTokenRecordCorruptedException()
            return record
        }

        override fun delete() {
            record = null
        }

        override fun exists(): Boolean = record != null
    }

    private fun proxyBridge(): NativeCalendarCoreBridge = Proxy.newProxyInstance(
        NativeCalendarCoreBridge::class.java.classLoader,
        arrayOf(NativeCalendarCoreBridge::class.java),
    ) { _, method, _ ->
        when (method.name) {
            "toString" -> "AuthTestFakeBridge"
            "hashCode" -> System.identityHashCode(this)
            "equals" -> false
            else -> throw AssertionError("Unexpected bridge call: " + method.name)
        }
    } as NativeCalendarCoreBridge

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
