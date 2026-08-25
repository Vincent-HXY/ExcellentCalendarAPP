package com.excellentcalendar.excellent_calendar.bridge.auth

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AuthRecordPatternsTest {
    @Test
    fun acceptsValidUuidsAndRejectsMalformedOnes() {
        assertTrue(AuthRecordPatterns.isUuid("62732653-c76a-40e7-bf72-bccabb54f06a"))
        assertFalse(AuthRecordPatterns.isUuid("not-a-uuid"))
        assertFalse(AuthRecordPatterns.isUuid("62732653-c76a-40e7-bf72-bccabb54f06"))
    }

    @Test
    fun acceptsRealUtcInstants() {
        assertTrue(AuthRecordPatterns.isValidUtcDateTime("2026-08-31T01:00:00Z"))
        assertTrue(AuthRecordPatterns.isValidUtcDateTime("2026-08-31T01:00:00.123Z"))
        assertTrue(AuthRecordPatterns.isValidUtcDateTime("2028-02-29T23:59:59Z"))
    }

    @Test
    fun rejectsImpossibleCalendarValues() {
        assertFalse(AuthRecordPatterns.isValidUtcDateTime("2026-13-99T99:99:99Z"))
        assertFalse(AuthRecordPatterns.isValidUtcDateTime("2026-02-29T00:00:00Z"))
        assertFalse(AuthRecordPatterns.isValidUtcDateTime("2026-04-31T00:00:00Z"))
        assertFalse(AuthRecordPatterns.isValidUtcDateTime("2026-08-31T24:00:00Z"))
        assertFalse(AuthRecordPatterns.isValidUtcDateTime("2026-08-31T01:00:00+08:00"))
        assertFalse(AuthRecordPatterns.isValidUtcDateTime("0000-01-01T00:00:00Z"))
    }
}
