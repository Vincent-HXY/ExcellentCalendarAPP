package com.excellentcalendar.excellent_calendar.bridge.sync

import org.junit.Assert.assertEquals
import org.junit.Assert.fail

internal const val GUEST = "11111111-1111-4111-8111-111111111111"
internal const val ACCOUNT = "22222222-2222-4222-8222-222222222222"
internal const val DEVICE = "33333333-3333-4333-8333-333333333333"
internal const val BOOT = "44444444-4444-4444-8444-444444444444"
internal const val NEXT_BOOT = "55555555-5555-4555-8555-555555555555"

internal fun failure(code: String, block: () -> Unit) {
    try { block(); fail("Expected $code") } catch (error: SyncLocalFailure) {
        assertEquals(code, error.code)
    }
}
