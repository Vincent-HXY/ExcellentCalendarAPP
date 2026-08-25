package com.excellentcalendar.excellent_calendar.bridge

import com.excellentcalendar.excellent_calendar.bridge.contract.AuthRefreshTokenContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeContractViolation
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class AuthRefreshTokenContractsTest {
    private val valid = mapOf(
        "refresh_token" to "opaque-refresh-token-value-at-least-32-characters",
        "session_id" to "62732653-c76a-40e7-bf72-bccabb54f06a",
        "expires_at" to "2026-08-31T01:00:00Z",
    )

    @Test
    fun validRequestParsesToRecord() {
        val record = AuthRefreshTokenContracts.storeRequest(valid)
        assertEquals("opaque-refresh-token-value-at-least-32-characters", record.refreshToken)
        assertEquals("62732653-c76a-40e7-bf72-bccabb54f06a", record.sessionId)
        assertEquals("2026-08-31T01:00:00Z", record.expiresAt)
    }

    @Test
    fun nonObjectRequestIsRejected() {
        assertThrows(NativeContractViolation::class.java) {
            AuthRefreshTokenContracts.storeRequest("not-a-map")
        }
    }

    @Test
    fun unknownFieldIsRejected() {
        assertThrows(NativeContractViolation::class.java) {
            AuthRefreshTokenContracts.storeRequest(valid + ("extra" to "x"))
        }
    }

    @Test
    fun missingFieldIsRejected() {
        assertThrows(NativeContractViolation::class.java) {
            AuthRefreshTokenContracts.storeRequest(valid - "session_id")
        }
    }

    @Test
    fun shortTokenIsRejected() {
        assertThrows(NativeContractViolation::class.java) {
            AuthRefreshTokenContracts.storeRequest(valid + ("refresh_token" to "short"))
        }
    }

    @Test
    fun badUuidIsRejected() {
        assertThrows(NativeContractViolation::class.java) {
            AuthRefreshTokenContracts.storeRequest(valid + ("session_id" to "not-a-uuid"))
        }
    }

    @Test
    fun nonUtcTimestampIsRejected() {
        assertThrows(NativeContractViolation::class.java) {
            AuthRefreshTokenContracts.storeRequest(valid + ("expires_at" to "2026-08-31T01:00:00+08:00"))
        }
    }
}
