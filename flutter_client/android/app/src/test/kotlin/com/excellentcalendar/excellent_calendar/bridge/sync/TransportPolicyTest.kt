package com.excellentcalendar.excellent_calendar.bridge.sync

import org.junit.Assert.*
import org.junit.Test

class TransportPolicyTest {
    @Test fun releaseAcceptsOnlyExplicitPublicHttpsHostname() {
        assertEquals("https://sync.example.org", EndpointPolicy.requireBaseUrl("https://sync.example.org", false).toString())
        listOf("", "http://sync.example.org", "https://10.0.2.2", "https://127.0.0.1", "https://[::1]",
            "https://192.168.1.3", "https://user:secret@sync.example.org", "https://localhost",
            "https://sync.example.org?token=x", "https://sync.example.org#fragment", "https://sync.example.org/path",
            "https://2130706433", "https://foo.local", "https://0x7f000001").forEach {
            failure("ENDPOINT_INVALID") { EndpointPolicy.requireBaseUrl(it, false) }
        }
    }
    @Test fun debugHttpOnlyAllowsLiteralPrivateAddresses() {
        listOf("http://10.0.2.2:8080", "http://192.168.0.5", "http://172.16.0.1", "http://172.31.255.254").forEach {
            assertNotNull(EndpointPolicy.requireBaseUrl(it, true))
        }
        listOf("http://example.org", "http://127.0.0.1", "http://172.32.0.1", "http://10.999.0.1", "http://10.0.2.2.evil.org").forEach {
            failure("ENDPOINT_INVALID") { EndpointPolicy.requireBaseUrl(it, true) }
        }
    }
    @Test fun jitterBudgetAndHintAreFrozen() {
        val upper = RetryPolicy { it }
        val lower = RetryPolicy { 0 }
        (0..7).forEach { attempt ->
            assertEquals(minOf(900_000L, 5_000L shl attempt), upper.delayMillis(attempt, null, null))
            assertEquals(0L, lower.delayMillis(attempt, null, null))
        }
        assertEquals(86_400_000L, lower.delayMillis(0, 86400, "86400"))
        assertEquals(5_000L, upper.delayMillis(0, 1, "1"))
        assertNull(upper.delayMillis(8, null, null))
        listOf(0, 86401, -1).forEach { hint -> failure("HTTP_ENVELOPE_INVALID") { upper.delayMillis(0, hint, null) } }
        failure("HTTP_ENVELOPE_INVALID") { upper.delayMillis(0, 3, "4") }
        failure("HTTP_ENVELOPE_INVALID") { upper.delayMillis(0, null, "3") }
        failure("HTTP_ENVELOPE_INVALID") { upper.delayMillis(0, 3, "Thu, 01 Jan 1970") }
        assertTrue(upper.retryableStatus(429)); assertTrue(upper.retryableStatus(503))
        assertFalse(upper.retryableStatus(501)); assertFalse(upper.retryableStatus(401))
    }
}
