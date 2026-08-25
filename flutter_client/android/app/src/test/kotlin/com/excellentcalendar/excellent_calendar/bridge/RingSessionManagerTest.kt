package com.excellentcalendar.excellent_calendar.bridge

import com.excellentcalendar.excellent_calendar.android.ring.RingPersistentState
import com.excellentcalendar.excellent_calendar.android.ring.RingPersistentStore
import com.excellentcalendar.excellent_calendar.bridge.ring.PreparedRingItem
import com.excellentcalendar.excellent_calendar.bridge.ring.RingSessionManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RingSessionManagerTest {
    @Test
    fun duplicateAttemptIsAddedOnceAndDoesNotExtendAudibleGeneration() {
        var elapsed = 1_000L
        val store = MemoryStore()
        val manager = manager(store) { elapsed }
        val first = item("1")
        assertTrue(manager.addPrepared(first).ok)
        assertTrue(manager.beginAudible(sound = true, vibration = false, durationMillis = 300_000).ok)
        val before = manager.activeSession()!!

        assertTrue(manager.addPrepared(first).ok)
        assertTrue(manager.addPrepared(item("2")).ok)
        val after = manager.activeSession()!!

        assertEquals(2, after.items.size)
        assertEquals(before.generation, after.generation)
        assertEquals(before.audibleDeadlineAt, after.audibleDeadlineAt)
        assertEquals(before.elapsedDeadlineMillis, after.elapsedDeadlineMillis)
    }

    @Test
    fun newItemDuringQuietStartsNewFiveMinuteGeneration() {
        var elapsed = 10_000L
        val manager = manager(MemoryStore()) { elapsed }
        manager.addPrepared(item("1"))
        manager.beginAudible(sound = true, vibration = false, durationMillis = 300_000)
        manager.enterQuiet()
        val quiet = manager.activeSession()!!
        elapsed = 50_000L

        manager.addPrepared(item("2"))
        manager.beginAudible(sound = false, vibration = true, durationMillis = 300_000)
        val audible = manager.activeSession()!!

        assertEquals(quiet.generation + 1, audible.generation)
        assertEquals(350_000L, audible.elapsedDeadlineMillis)
        assertEquals("audible", audible.phase)
    }

    @Test
    fun removingLastItemPersistsResolvedSnapshot() {
        val store = MemoryStore()
        val manager = manager(store) { 0L }
        manager.addPrepared(item("1"))
        val revision = manager.activeSession()!!.revision

        assertTrue(manager.remove(listOf(item("1").deliveryId)).ok)

        assertNull(manager.activeSession())
        assertEquals(revision + 1, store.state.sessionRevision)
        assertNull(store.state.activeSession)
    }

    @Test
    fun eventListenerFailureDoesNotMasqueradeAsStorageFailure() {
        val store = MemoryStore()
        val manager = manager(store) { 0L }
        manager.setListener { _, _ -> error("detached Flutter event sink") }

        val result = manager.addPrepared(item("1"))

        assertTrue(result.ok)
        assertEquals(1, store.state.activeSession?.items?.size)
        assertEquals(1, manager.activeSession()?.items?.size)
    }

    private fun manager(store: RingPersistentStore, elapsed: () -> Long) = RingSessionManager(
        store = store,
        capabilities = { settings ->
            linkedMapOf(
                "evaluated_at" to "2026-08-22T00:00:00Z",
                "sdk_int" to 36,
                "notification_permission" to "granted",
                "exact_alarm_permission" to "granted",
                "full_screen_intent_permission" to "granted",
                "can_post_notifications" to true,
                "can_schedule_exact_alarms" to true,
                "can_use_full_screen_intent" to true,
                "ring_channel_enabled" to true,
                "has_audio_output" to true,
                "has_vibrator" to true,
                "can_enable_ring" to true,
                "blocking_reasons" to emptyList<String>(),
                "degradation_reasons" to if (settings.ringtoneAvailable) emptyList<String>() else listOf("selected_ringtone_unavailable"),
            )
        },
        nowUtc = { "2026-08-22T00:00:00Z" },
        elapsedRealtime = elapsed,
        runtimeInstanceId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    )

    private fun item(suffix: String): PreparedRingItem {
        val digit = suffix.padStart(12, '0')
        return PreparedRingItem(
            notificationId = "10000000-0000-4000-8000-$digit",
            deliveryId = "20000000-0000-4000-8000-$digit",
            deliveryAttemptId = "30000000-0000-4000-8000-$digit",
            reminderId = "40000000-0000-4000-8000-$digit",
            eventId = "50000000-0000-4000-8000-$digit",
            recoveryBatchId = null,
            plannedAt = "2026-08-22T00:00:00Z",
        )
    }

    private class MemoryStore : RingPersistentStore {
        var state = RingPersistentState()
        override fun load(): RingPersistentState = state
        override fun save(state: RingPersistentState) {
            this.state = state
        }
    }
}
