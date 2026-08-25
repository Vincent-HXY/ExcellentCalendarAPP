package com.excellentcalendar.excellent_calendar.bridge.auth

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class RefreshTokenRecordCodecTest {
    private val record = SecureRefreshTokenRecord(
        refreshToken = "opaque-refresh-token-value-at-least-32-characters",
        sessionId = "62732653-c76a-40e7-bf72-bccabb54f06a",
        expiresAt = "2026-08-31T01:00:00Z",
    )

    @Test
    fun encodeDecodeRoundTripPreservesAllFields() {
        val decoded = RefreshTokenRecordCodec.decode(RefreshTokenRecordCodec.encode(record))
        assertEquals(record, decoded)
    }

    @Test
    fun decodeRejectsNonJsonContent() {
        assertThrows(RefreshTokenRecordCorruptedException::class.java) {
            RefreshTokenRecordCodec.decode("not-json".toByteArray())
        }
    }

    @Test
    fun decodeRejectsMissingField() {
        val json = """{"refresh_token":"opaque-refresh-token-value-at-least-32-characters","session_id":"62732653-c76a-40e7-bf72-bccabb54f06a"}"""
        assertThrows(RefreshTokenRecordCorruptedException::class.java) {
            RefreshTokenRecordCodec.decode(json.toByteArray())
        }
    }

    @Test
    fun decodeRejectsUnknownField() {
        val json = """{"refresh_token":"opaque-refresh-token-value-at-least-32-characters","session_id":"62732653-c76a-40e7-bf72-bccabb54f06a","expires_at":"2026-08-31T01:00:00Z","extra":"x"}"""
        assertThrows(RefreshTokenRecordCorruptedException::class.java) {
            RefreshTokenRecordCodec.decode(json.toByteArray())
        }
    }

    @Test
    fun decodeRejectsShortTokenBadUuidAndBadTimestamp() {
        val shortToken = """{"refresh_token":"short","session_id":"62732653-c76a-40e7-bf72-bccabb54f06a","expires_at":"2026-08-31T01:00:00Z"}"""
        assertThrows(RefreshTokenRecordCorruptedException::class.java) {
            RefreshTokenRecordCodec.decode(shortToken.toByteArray())
        }
        val badUuid = """{"refresh_token":"opaque-refresh-token-value-at-least-32-characters","session_id":"not-a-uuid","expires_at":"2026-08-31T01:00:00Z"}"""
        assertThrows(RefreshTokenRecordCorruptedException::class.java) {
            RefreshTokenRecordCodec.decode(badUuid.toByteArray())
        }
        val badTime = """{"refresh_token":"opaque-refresh-token-value-at-least-32-characters","session_id":"62732653-c76a-40e7-bf72-bccabb54f06a","expires_at":"2026-08-31 01:00:00"}"""
        assertThrows(RefreshTokenRecordCorruptedException::class.java) {
            RefreshTokenRecordCodec.decode(badTime.toByteArray())
        }
    }
}
