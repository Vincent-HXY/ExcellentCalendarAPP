package com.excellentcalendar.excellent_calendar.bridge.sync

import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class RetentionClockTest {
    private class Store : BootRecordStore {
        var record: BootRecord? = null
        var broken = false
        override fun read(): BootRecord? { if (broken) throw IllegalStateException(); return record }
        override fun write(value: BootRecord) { if (broken) throw IllegalStateException(); record = value }
    }
    @Test fun sameBootRestoresAcrossProcessButSystemRebootChangesIdentity() {
        val store = Store()
        assertEquals(BOOT, BootEpochProvider(store) { BOOT }.observe(24, 7, 100).id)
        assertEquals(BOOT, BootEpochProvider(store) { NEXT_BOOT }.observe(24, 7, 110).id)
        assertEquals(110L, store.record!!.elapsedMillis)
        assertEquals(NEXT_BOOT, BootEpochProvider(store) { NEXT_BOOT }.observe(24, 8, 1).id)
    }
    @Test fun api23UsesOnlyCurrentProcessToken() {
        val store = Store()
        val first = BootEpochProvider(store) { BOOT }
        assertEquals(BOOT, first.observe(23, null, 100).id)
        assertEquals(BOOT, first.observe(23, null, 120).id)
        assertEquals(NEXT_BOOT, BootEpochProvider(store) { NEXT_BOOT }.observe(23, null, 130).id)
    }
    @Test fun rollbackCorruptionAndDuplicateUuidNeverAuthorizeOldAnchor() {
        val store = Store()
        BootEpochProvider(store) { BOOT }.observe(24, 7, 100)
        failure("RETENTION_TRUSTED_TIME_REQUIRED") { BootEpochProvider(store) { NEXT_BOOT }.observe(24, 7, 99) }
        failure("RETENTION_TRUSTED_TIME_REQUIRED") { BootEpochProvider(store) { NEXT_BOOT }.observe(24, 6, 101) }
        failure("RETENTION_TRUSTED_TIME_REQUIRED") { BootEpochProvider(store) { BOOT }.observe(24, 8, 1) }
        store.broken = true
        failure("RETENTION_TRUSTED_TIME_REQUIRED") { BootEpochProvider(store) { NEXT_BOOT }.observe(24, 8, 1) }
    }
    @Test fun retentionNeverUsesWallClockOrExtendsDeadline() {
        val server = Instant.parse("2026-09-07T00:00:00Z")
        val anchor = TrustedTimeAnchor(server, BOOT, 100)
        val record = RetentionClock.retain(anchor, BootObservation(BOOT, 1_100))
        assertEquals(server.plusSeconds(1), record.startedAt)
        assertEquals(server.plusSeconds(2_592_001), record.until)
        assertFalse(RetentionClock.expired(record, BootObservation(NEXT_BOOT, Long.MAX_VALUE)))
        assertFalse(RetentionClock.expired(record, BootObservation(BOOT, 1_099)))
        assertTrue(RetentionClock.expired(record, BootObservation(BOOT, 2_592_001_100)))
        assertFalse(RetentionClock.expired(record, BootObservation(NEXT_BOOT, 50), record.until.minusSeconds(1)))
        assertTrue(RetentionClock.expired(record, BootObservation(NEXT_BOOT, 50), record.until))
        assertEquals(server.plusSeconds(2_592_001), record.until)
        failure("RETENTION_TRUSTED_TIME_REQUIRED") { RetentionClock.retain(null, BootObservation(BOOT, 1)) }
        failure("RETENTION_TRUSTED_TIME_REQUIRED") { RetentionClock.retain(anchor, BootObservation(NEXT_BOOT, 1100)) }
    }
}
