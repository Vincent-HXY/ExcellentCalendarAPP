package com.excellentcalendar.excellent_calendar.bridge.ring

import com.excellentcalendar.excellent_calendar.android.ring.RingCapabilityProvider
import com.excellentcalendar.excellent_calendar.android.ring.RingItemRecord
import com.excellentcalendar.excellent_calendar.android.ring.RingPersistentState
import com.excellentcalendar.excellent_calendar.android.ring.RingPersistentStore
import com.excellentcalendar.excellent_calendar.android.ring.RingSessionRecord
import com.excellentcalendar.excellent_calendar.android.ring.RingSettingsRecord
import com.excellentcalendar.excellent_calendar.android.ring.ringUtcFromMillis
import com.excellentcalendar.excellent_calendar.android.ring.ringUtcNow
import com.excellentcalendar.excellent_calendar.android.ring.ringUtcToMillis
import com.excellentcalendar.excellent_calendar.bridge.contract.ActiveRingItemsContract
import com.excellentcalendar.excellent_calendar.bridge.contract.CompleteRingItemContract
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import java.util.UUID

data class PreparedRingItem(
    val notificationId: String,
    val deliveryId: String,
    val deliveryAttemptId: String,
    val reminderId: String,
    val eventId: String,
    val recoveryBatchId: String?,
    val plannedAt: String,
)

fun interface RingStateListener {
    fun onStateChanged(reason: String, event: Map<String, Any?>)
}

class RingSessionManager(
    private val store: RingPersistentStore,
    private val capabilities: RingCapabilityProvider,
    private val nowUtc: () -> String = ::ringUtcNow,
    private val elapsedRealtime: () -> Long,
    private val runtimeInstanceId: String = UUID.randomUUID().toString(),
) {
    private var sequence = 0L
    private var testState = "inactive"
    private var listener: RingStateListener? = null
    private var persistenceError: Throwable? = null
    private var state = try {
        store.load()
    } catch (error: Throwable) {
        persistenceError = error
        RingPersistentState()
    }

    @Synchronized
    fun setListener(value: RingStateListener?) {
        listener = value
    }

    @Synchronized
    fun getState(): NativeResultContract {
        persistenceError?.let {
            return failure(NativeErrorCodes.RingSettingsCorrupted, "Device-local ring state cannot be decoded safely.", false)
        }
        return runCatching { NativeResultContract.success(snapshot(), contractVersion = 2) }
            .getOrElse { failure(NativeErrorCodes.RingCapabilityUnavailable, "Android ring capability cannot be evaluated.", true) }
    }

    @Synchronized
    fun currentSnapshot(): Map<String, Any?> = snapshot()

    @Synchronized
    fun settings(): RingSettingsRecord = state.settings

    @Synchronized
    fun updateSettings(expectedRevision: Long, strongReminderEnabled: Boolean): NativeResultContract {
        val conflict = settingsConflict(expectedRevision)
        if (conflict != null) return conflict
        return persist(
            state.copy(settings = state.settings.copy(
                revision = state.settings.revision + 1,
                strongReminderEnabled = strongReminderEnabled,
            )),
            "settings_changed",
        )
    }

    @Synchronized
    fun updateRingtone(expectedRevision: Long, uri: String, displayName: String, available: Boolean): NativeResultContract {
        val conflict = settingsConflict(expectedRevision)
        if (conflict != null) return conflict
        return persist(
            state.copy(settings = state.settings.copy(
                revision = state.settings.revision + 1,
                ringtoneUri = uri,
                ringtoneDisplayName = displayName.ifBlank { "Selected alarm" },
                ringtoneAvailable = available,
            )),
            "settings_changed",
        )
    }

    @Synchronized
    fun setTestState(expectedRevision: Long, audible: Boolean): NativeResultContract {
        val conflict = settingsConflict(expectedRevision)
        if (conflict != null) return conflict
        if (audible && state.activeSession != null) {
            return failure(NativeErrorCodes.RingSessionConflict, "A live ring session is already active.", true)
        }
        testState = if (audible) "audible" else "inactive"
        emit("test_changed")
        return NativeResultContract.success(snapshot(), contractVersion = 2)
    }

    @Synchronized
    fun addPrepared(item: PreparedRingItem): NativeResultContract {
        val current = state.activeSession
        if (current?.items?.any { it.deliveryAttemptId == item.deliveryAttemptId || it.deliveryId == item.deliveryId } == true) {
            return NativeResultContract.success(snapshot(), contractVersion = 2)
        }
        val now = nowUtc()
        val storedItem = RingItemRecord(
            item.notificationId,
            item.deliveryId,
            item.deliveryAttemptId,
            item.reminderId,
            item.eventId,
            item.recoveryBatchId,
            item.plannedAt,
            now,
        )
        val nextRevision = state.sessionRevision + 1
        val session = if (current == null) {
            RingSessionRecord(
                sessionId = UUID.randomUUID().toString(),
                revision = nextRevision,
                phase = "prepared",
                generation = 0,
                startedAt = now,
                phaseChangedAt = now,
                audibleStartedAt = null,
                audibleDeadlineAt = null,
                quietSince = null,
                elapsedDeadlineMillis = null,
                controlNotificationVisible = false,
                soundActive = false,
                vibrationActive = false,
                items = listOf(storedItem),
            )
        } else {
            current.copy(revision = nextRevision, items = current.items + storedItem)
        }
        return persist(state.copy(sessionRevision = nextRevision, activeSession = session), "session_changed")
    }

    @Synchronized
    fun beginAudible(sound: Boolean, vibration: Boolean, durationMillis: Long): NativeResultContract {
        if (!sound && !vibration) return failure(NativeErrorCodes.RingOutputUnavailable, "Neither sound nor vibration could be started.", false)
        val current = state.activeSession ?: return failure(NativeErrorCodes.RingSessionNotFound, "No active ring session exists.", false)
        if (current.phase == "audible") {
            val nextRevision = state.sessionRevision + 1
            return persist(
                state.copy(sessionRevision = nextRevision, activeSession = current.copy(
                    revision = nextRevision,
                    controlNotificationVisible = true,
                    soundActive = sound,
                    vibrationActive = vibration,
                )),
                "session_changed",
            )
        }
        val now = nowUtc()
        val nextRevision = state.sessionRevision + 1
        val audible = current.copy(
            revision = nextRevision,
            phase = "audible",
            generation = current.generation + 1,
            phaseChangedAt = now,
            audibleStartedAt = now,
            audibleDeadlineAt = ringUtcFromMillis(ringUtcToMillis(now) + durationMillis),
            quietSince = null,
            elapsedDeadlineMillis = elapsedRealtime() + durationMillis,
            controlNotificationVisible = true,
            soundActive = sound,
            vibrationActive = vibration,
        )
        return persist(state.copy(sessionRevision = nextRevision, activeSession = audible), "session_changed")
    }

    @Synchronized
    fun markControlVisible(): NativeResultContract {
        val current = state.activeSession ?: return failure(NativeErrorCodes.RingSessionNotFound, "No active ring session exists.", false)
        if (current.controlNotificationVisible) return NativeResultContract.success(snapshot(), contractVersion = 2)
        val nextRevision = state.sessionRevision + 1
        return persist(
            state.copy(sessionRevision = nextRevision, activeSession = current.copy(revision = nextRevision, controlNotificationVisible = true)),
            "session_changed",
        )
    }

    @Synchronized
    fun enterQuiet(): NativeResultContract {
        val current = state.activeSession ?: return failure(NativeErrorCodes.RingSessionNotFound, "No active ring session exists.", false)
        if (current.phase != "audible") return NativeResultContract.success(snapshot(), contractVersion = 2)
        val now = nowUtc()
        val nextRevision = state.sessionRevision + 1
        return persist(
            state.copy(sessionRevision = nextRevision, activeSession = current.copy(
                revision = nextRevision,
                phase = "quiet_pending",
                phaseChangedAt = now,
                quietSince = now,
                elapsedDeadlineMillis = null,
                soundActive = false,
                vibrationActive = false,
            )),
            "session_changed",
        )
    }

    @Synchronized
    fun markFinalizeOutcome(deliveryId: String, outcome: String): NativeResultContract {
        val current = state.activeSession ?: return failure(NativeErrorCodes.RingSessionNotFound, "No active ring session exists.", false)
        if (current.items.none { it.deliveryId == deliveryId }) return failure(NativeErrorCodes.RingItemNotFound, "Ring item was removed.", false)
        val nextRevision = state.sessionRevision + 1
        val updated = current.copy(
            revision = nextRevision,
            items = current.items.map { if (it.deliveryId == deliveryId) it.copy(finalizeOutcome = outcome) else it },
        )
        return persist(state.copy(sessionRevision = nextRevision, activeSession = updated), "session_changed")
    }

    @Synchronized
    fun validate(request: ActiveRingItemsContract): NativeResultContract? = validateIdentity(
        request.runtimeInstanceId,
        request.sessionId,
        request.expectedSessionRevision,
        request.deliveryIds,
    )

    @Synchronized
    fun validate(request: CompleteRingItemContract): NativeResultContract? = validateIdentity(
        request.runtimeInstanceId,
        request.sessionId,
        request.expectedSessionRevision,
        listOf(request.deliveryId),
    )

    @Synchronized
    fun items(deliveryIds: List<String>): List<RingItemRecord> {
        val byId = state.activeSession?.items?.associateBy { it.deliveryId }.orEmpty()
        return deliveryIds.mapNotNull(byId::get)
    }

    @Synchronized
    fun remove(deliveryIds: Collection<String>): NativeResultContract {
        val current = state.activeSession ?: return failure(NativeErrorCodes.RingSessionNotFound, "No active ring session exists.", false)
        val remaining = current.items.filterNot { it.deliveryId in deliveryIds }
        if (remaining.size == current.items.size) return failure(NativeErrorCodes.RingItemNotFound, "No requested ring item exists.", false)
        val nextRevision = state.sessionRevision + 1
        val nextSession = if (remaining.isEmpty()) null else current.copy(revision = nextRevision, items = remaining)
        return persist(state.copy(sessionRevision = nextRevision, activeSession = nextSession), "session_changed")
    }

    @Synchronized
    fun activeSession(): RingSessionRecord? = state.activeSession

    @Synchronized
    fun emitRecovered() {
        if (state.activeSession != null) emit("session_recovered")
    }

    private fun validateIdentity(runtimeId: String, sessionId: String, revision: Long, deliveryIds: List<String>): NativeResultContract? {
        if (runtimeId != runtimeInstanceId) return failure(NativeErrorCodes.RingSessionConflict, "Ring runtime instance changed.", true)
        val current = state.activeSession ?: return failure(NativeErrorCodes.RingSessionNotFound, "No active ring session exists.", false)
        if (current.sessionId != sessionId || current.revision != revision) {
            return failure(NativeErrorCodes.RingSessionConflict, "Active ring session changed before the action.", true)
        }
        if (!current.items.map { it.deliveryId }.containsAll(deliveryIds)) {
            return failure(NativeErrorCodes.RingItemNotFound, "One or more ring items do not exist.", false)
        }
        return null
    }

    private fun settingsConflict(expected: Long): NativeResultContract? = if (state.settings.revision != expected) {
        failure(NativeErrorCodes.RingSettingsConflict, "Ring settings changed before the update.", true)
    } else null

    private fun persist(next: RingPersistentState, reason: String): NativeResultContract {
        try {
            store.save(next)
        } catch (_: Throwable) {
            return failure(NativeErrorCodes.RingSettingsStorageFailed, "Device-local ring state could not be persisted.", true)
        }
        state = next
        persistenceError = null
        emit(reason)
        return NativeResultContract.success(snapshot(), contractVersion = 2)
    }

    private fun emit(reason: String) {
        sequence += 1
        runCatching {
            listener?.onStateChanged(reason, linkedMapOf("reason" to reason, "state" to snapshot()))
        }
    }

    private fun snapshot(): Map<String, Any?> {
        val capability = capabilities.snapshot(state.settings)
        val selectedUnavailable = (capability["degradation_reasons"] as? List<*>)
            ?.contains("selected_ringtone_unavailable") == true
        return linkedMapOf(
            "captured_at" to nowUtc(),
            "runtime_instance_id" to runtimeInstanceId,
            "sequence" to sequence,
            "session_revision" to state.sessionRevision,
            "settings" to state.settings.toContractMap().toMutableMap().apply {
                this["ringtone_available"] = state.settings.ringtoneAvailable && !selectedUnavailable
            },
            "capability" to capability,
            "active_session" to state.activeSession?.toContractMap(),
            "test_state" to testState,
        )
    }

    private fun RingSettingsRecord.toContractMap(): Map<String, Any?> = linkedMapOf(
        "revision" to revision,
        "ringtone_display_name" to ringtoneDisplayName,
        "ringtone_available" to ringtoneAvailable,
        "strong_reminder_enabled" to strongReminderEnabled,
    )

    private fun RingSessionRecord.toContractMap(): Map<String, Any?> = linkedMapOf(
        "session_id" to sessionId,
        "revision" to revision,
        "phase" to phase,
        "generation" to generation,
        "started_at" to startedAt,
        "phase_changed_at" to phaseChangedAt,
        "audible_started_at" to audibleStartedAt,
        "audible_deadline_at" to audibleDeadlineAt,
        "quiet_since" to quietSince,
        "control_notification_visible" to controlNotificationVisible,
        "sound_active" to soundActive,
        "vibration_active" to vibrationActive,
        "items" to items.map {
            linkedMapOf(
                "notification_id" to it.notificationId,
                "delivery_id" to it.deliveryId,
                "delivery_attempt_id" to it.deliveryAttemptId,
                "reminder_id" to it.reminderId,
                "event_id" to it.eventId,
                "recovery_batch_id" to it.recoveryBatchId,
                "planned_at" to it.plannedAt,
                "added_at" to it.addedAt,
            )
        },
    )

    private fun failure(code: String, message: String, retryable: Boolean): NativeResultContract =
        NativeResultContract.failure(code, message, retryable = retryable, contractVersion = 2)
}
