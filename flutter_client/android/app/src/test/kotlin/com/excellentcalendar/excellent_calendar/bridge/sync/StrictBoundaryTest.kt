package com.excellentcalendar.excellent_calendar.bridge.sync

import org.junit.Assert.*
import org.junit.Test

class StrictBoundaryTest {
    private val valid = """{"ok":true,"data":{"n":9007199254740991},"error":null,"contract_version":3,"request_id":"test"}"""
    @Test fun nativeAndHttpEnvelopesCannotBeInterchanged() {
        assertTrue(StrictBoundary.envelope(valid.toByteArray(), 3).getBoolean("ok"))
        failure("HTTP_ENVELOPE_INVALID") { StrictBoundary.envelope(valid.toByteArray(), 1) }
        assertTrue(StrictBoundary.envelope(valid.replace("version\":3", "version\":1").toByteArray(), 1).getBoolean("ok"))
    }
    @Test fun malformedWireFailsBeforeAnyConsumer() {
        listOf(valid.replace("true", "\"true\""), valid.replace("9007199254740991", "9007199254740992"),
            valid.replace("\"error\":null", "\"error\":{}"), valid.replace("\"error\":null,", ""),
            valid.replace("\"ok\":true", "\"ok\":true,\"ok\":false"),
            valid.dropLast(1) + ",\"secret\":1}", valid + "{}", valid.replace("\"n\"", "n"),
            valid.replace("9007199254740991", "NaN"), valid.replace("\"test\"", "'test'"),
            valid.replace("\"test\"", "\"\\ud800\""), valid.replace("9007199254740991", "01"),
            valid.replace("\"ok\":true", "\"ok\":true,\"\\u006fk\":false")).forEach {
            failure("HTTP_ENVELOPE_INVALID") { StrictBoundary.envelope(it.toByteArray(), 3) }
        }
        failure("HTTP_ENVELOPE_INVALID") { StrictBoundary.envelope(byteArrayOf(0xc3.toByte(), 0x28), 3) }
        failure("HTTP_ENVELOPE_INVALID") { StrictBoundary.envelope(valid.toByteArray(), 3, 10) }
        failure("HTTP_ENVELOPE_INVALID") {
            StrictBoundary.envelope("""{"ok":false,"data":null,"error":{},"contract_version":3,"request_id":"test"}""".toByteArray(), 3)
        }
    }
    @Test fun rawPayloadIsNotRebuiltAndDepthIsBounded() {
        val payload = """{ "文字": "😀", "fraction": 0.25, "negative": -2 }"""
        assertEquals(payload, StrictBoundary.requireJson(payload.toByteArray()))
        failure("HTTP_ENVELOPE_INVALID") { StrictBoundary.requireJson(("[".repeat(70) + "0" + "]".repeat(70)).toByteArray()) }
    }
}
