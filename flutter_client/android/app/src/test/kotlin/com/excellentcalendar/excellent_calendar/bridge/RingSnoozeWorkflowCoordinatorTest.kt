package com.excellentcalendar.excellent_calendar.bridge

import com.excellentcalendar.excellent_calendar.android.ring.RingPersistentState
import com.excellentcalendar.excellent_calendar.android.ring.RingPersistentStore
import com.excellentcalendar.excellent_calendar.bridge.contract.ActiveRingItemsContract
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorContract
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.ring.PreparedRingItem
import com.excellentcalendar.excellent_calendar.bridge.ring.RingSessionManager
import com.excellentcalendar.excellent_calendar.bridge.ring.RingSnoozeItemOutcome
import com.excellentcalendar.excellent_calendar.bridge.ring.RingSnoozeWorkflowCoordinator
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RingSnoozeWorkflowCoordinatorTest {
    @Test
    fun partialSuccessRemovesOnlyCommittedItemsAndReconcilesOnce() {
        val store = MemoryStore()
        val manager = manager(store)
        val first = item("1")
        val second = item("2")
        manager.addPrepared(first)
        manager.addPrepared(second)
        val session = manager.activeSession()!!
        var snoozeCalls = 0
        var reconcileCalls = 0
        val coordinator = RingSnoozeWorkflowCoordinator(
            manager = manager,
            snoozeItem = { item ->
                snoozeCalls += 1
                if (item.deliveryId == first.deliveryId) {
                    RingSnoozeItemOutcome(item.deliveryId, SnoozedReminderId, null)
                } else {
                    RingSnoozeItemOutcome(
                        item.deliveryId,
                        null,
                        NativeErrorContract(
                            NativeErrorCodes.ReminderSnoozeNotAllowed,
                            "snooze rejected",
                            null,
                            false,
                        ),
                    )
                }
            },
            afterSnoozeCommitted = {
                reconcileCalls += 1
                true
            },
        )
        val request = ActiveRingItemsContract(
            RuntimeId,
            session.sessionId,
            session.revision,
            listOf(first.deliveryId, second.deliveryId),
        )

        val result = coordinator.snooze(request)

        assertTrue(result.ok)
        @Suppress("UNCHECKED_CAST")
        val data = result.data as Map<String, Any?>
        assertEquals(1, data["succeeded_count"])
        assertEquals(1, data["failed_count"])
        @Suppress("UNCHECKED_CAST")
        val state = data["state"] as Map<String, Any?>
        @Suppress("UNCHECKED_CAST")
        val activeSession = state["active_session"] as Map<String, Any?>
        @Suppress("UNCHECKED_CAST")
        val items = activeSession["items"] as List<Map<String, Any?>>
        assertEquals(listOf(second.deliveryId), items.map { it["delivery_id"] })
        assertEquals(2, snoozeCalls)
        assertEquals(1, reconcileCalls)

        val staleReplay = coordinator.snooze(request)
        assertFalse(staleReplay.ok)
        assertEquals(NativeErrorCodes.RingSessionConflict, staleReplay.error?.code)
        assertEquals(2, snoozeCalls)

        val recoveredManager = manager(store)
        assertEquals(listOf(second.deliveryId), recoveredManager.activeSession()?.items?.map { it.deliveryId })
    }

    @Test
    fun committedSnoozeReportsPendingCleanupWhenSessionPersistenceFails() {
        val store = MemoryStore()
        val manager = manager(store)
        val prepared = item("1")
        manager.addPrepared(prepared)
        val session = manager.activeSession()!!
        var reconcileCalls = 0
        val coordinator = RingSnoozeWorkflowCoordinator(
            manager = manager,
            snoozeItem = { RingSnoozeItemOutcome(it.deliveryId, SnoozedReminderId, null) },
            afterSnoozeCommitted = {
                reconcileCalls += 1
                true
            },
        )
        store.failNextSave = true

        val result = coordinator.snooze(
            ActiveRingItemsContract(RuntimeId, session.sessionId, session.revision, listOf(prepared.deliveryId)),
        )

        assertFalse(result.ok)
        assertEquals(NativeErrorCodes.RingSettingsStorageFailed, result.error?.code)
        assertEquals(true, result.error?.details?.get("snooze_committed"))
        assertEquals(true, result.error?.details?.get("session_cleanup_pending"))
        assertEquals(listOf(prepared.deliveryId), result.error?.details?.get("committed_delivery_ids"))
        assertEquals(1, manager.activeSession()?.items?.size)
        assertEquals(1, reconcileCalls)
    }

    @Test
    fun committedSnoozeStopsCurrentRingAndReportsDeferredAndroidScheduling() {
        val store = MemoryStore()
        val manager = manager(store)
        val prepared = item("1")
        manager.addPrepared(prepared)
        val session = manager.activeSession()!!
        val coordinator = RingSnoozeWorkflowCoordinator(
            manager = manager,
            snoozeItem = { RingSnoozeItemOutcome(it.deliveryId, SnoozedReminderId, null) },
            afterSnoozeCommitted = { false },
        )

        val result = coordinator.snooze(
            ActiveRingItemsContract(RuntimeId, session.sessionId, session.revision, listOf(prepared.deliveryId)),
        )

        assertFalse(result.ok)
        assertEquals(NativeErrorCodes.AlarmScheduleFailed, result.error?.code)
        assertEquals(true, result.error?.details?.get("snooze_committed"))
        assertEquals(false, result.error?.details?.get("session_cleanup_pending"))
        assertEquals(true, result.error?.details?.get("schedule_reconcile_deferred"))
        assertEquals(null, manager.activeSession())
        assertEquals(null, store.state.activeSession)
    }

    private fun manager(store: RingPersistentStore) = RingSessionManager(
        store = store,
        capabilities = { settings ->
            linkedMapOf(
                "evaluated_at" to "2026-08-23T00:00:00Z",
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
        nowUtc = { "2026-08-23T00:00:00Z" },
        elapsedRealtime = { 0L },
        runtimeInstanceId = RuntimeId,
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
            plannedAt = "2026-08-23T00:00:00Z",
        )
    }

    private class MemoryStore : RingPersistentStore {
        var state = RingPersistentState()
        var failNextSave = false

        override fun load(): RingPersistentState = state

        override fun save(state: RingPersistentState) {
            if (failNextSave) {
                failNextSave = false
                error("injected storage failure")
            }
            this.state = state
        }
    }

    companion object {
        private const val RuntimeId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        private const val SnoozedReminderId = "60000000-0000-4000-8000-000000000001"
    }
}
