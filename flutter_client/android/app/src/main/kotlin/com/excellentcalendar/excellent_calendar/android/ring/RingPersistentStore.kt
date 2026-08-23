package com.excellentcalendar.excellent_calendar.android.ring

import android.content.Context
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec

data class RingSettingsRecord(
    val revision: Long = 0,
    val ringtoneDisplayName: String = "Default alarm",
    val ringtoneAvailable: Boolean = true,
    val strongReminderEnabled: Boolean = false,
    val ringtoneUri: String? = null,
)

data class RingItemRecord(
    val notificationId: String,
    val deliveryId: String,
    val deliveryAttemptId: String,
    val reminderId: String,
    val eventId: String,
    val recoveryBatchId: String?,
    val plannedAt: String,
    val addedAt: String,
    val finalizeOutcome: String? = null,
)

data class RingSessionRecord(
    val sessionId: String,
    val revision: Long,
    val phase: String,
    val generation: Long,
    val startedAt: String,
    val phaseChangedAt: String,
    val audibleStartedAt: String?,
    val audibleDeadlineAt: String?,
    val quietSince: String?,
    val elapsedDeadlineMillis: Long?,
    val controlNotificationVisible: Boolean,
    val soundActive: Boolean,
    val vibrationActive: Boolean,
    val items: List<RingItemRecord>,
)

data class RingPersistentState(
    val sessionRevision: Long = 0,
    val settings: RingSettingsRecord = RingSettingsRecord(),
    val activeSession: RingSessionRecord? = null,
)

interface RingPersistentStore {
    fun load(): RingPersistentState
    fun save(state: RingPersistentState)
}

class AndroidRingPersistentStore(context: Context) : RingPersistentStore {
    private val preferences = context.applicationContext.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)

    @Synchronized
    override fun load(): RingPersistentState {
        val json = preferences.getString(KeyState, null) ?: return RingPersistentState()
        val root = NativeContractJsonCodec.decodeObject(json)
        if (number(root["schema_version"]) != SchemaVersion) error("Unsupported ring state schema version.")
        val settingsMap = objectMap(root["settings"])
        val settings = RingSettingsRecord(
            revision = number(settingsMap["revision"]),
            ringtoneDisplayName = string(settingsMap["ringtone_display_name"]),
            ringtoneAvailable = bool(settingsMap["ringtone_available"]),
            strongReminderEnabled = bool(settingsMap["strong_reminder_enabled"]),
            ringtoneUri = nullableString(settingsMap["ringtone_uri"]),
        )
        val session = root["active_session"]?.let { value ->
            val map = objectMap(value)
            val rawItems = map["items"] as? List<*> ?: error("Ring session items are malformed.")
            val items = rawItems.map { raw ->
                val item = objectMap(raw)
                RingItemRecord(
                    notificationId = string(item["notification_id"]),
                    deliveryId = string(item["delivery_id"]),
                    deliveryAttemptId = string(item["delivery_attempt_id"]),
                    reminderId = string(item["reminder_id"]),
                    eventId = string(item["event_id"]),
                    recoveryBatchId = nullableString(item["recovery_batch_id"]),
                    plannedAt = string(item["planned_at"]),
                    addedAt = string(item["added_at"]),
                    finalizeOutcome = nullableString(item["finalize_outcome"]),
                )
            }
            if (items.isEmpty()) error("Active ring session cannot be empty.")
            RingSessionRecord(
                sessionId = string(map["session_id"]),
                revision = number(map["revision"]),
                phase = string(map["phase"]),
                generation = number(map["generation"]),
                startedAt = string(map["started_at"]),
                phaseChangedAt = string(map["phase_changed_at"]),
                audibleStartedAt = nullableString(map["audible_started_at"]),
                audibleDeadlineAt = nullableString(map["audible_deadline_at"]),
                quietSince = nullableString(map["quiet_since"]),
                elapsedDeadlineMillis = nullableNumber(map["elapsed_deadline_millis"]),
                controlNotificationVisible = bool(map["control_notification_visible"]),
                soundActive = bool(map["sound_active"]),
                vibrationActive = bool(map["vibration_active"]),
                items = items,
            )
        }
        return RingPersistentState(number(root["session_revision"]), settings, session)
    }

    @Synchronized
    override fun save(state: RingPersistentState) {
        val root = linkedMapOf<String, Any?>(
            "schema_version" to SchemaVersion,
            "session_revision" to state.sessionRevision,
            "settings" to linkedMapOf(
                "revision" to state.settings.revision,
                "ringtone_display_name" to state.settings.ringtoneDisplayName,
                "ringtone_available" to state.settings.ringtoneAvailable,
                "strong_reminder_enabled" to state.settings.strongReminderEnabled,
                "ringtone_uri" to state.settings.ringtoneUri,
            ),
            "active_session" to state.activeSession?.toPersistentMap(),
        )
        if (!preferences.edit().putString(KeyState, NativeContractJsonCodec.encodeObject(root)).commit()) {
            error("Cannot persist ring state.")
        }
    }

    private fun RingSessionRecord.toPersistentMap(): Map<String, Any?> = linkedMapOf(
        "session_id" to sessionId,
        "revision" to revision,
        "phase" to phase,
        "generation" to generation,
        "started_at" to startedAt,
        "phase_changed_at" to phaseChangedAt,
        "audible_started_at" to audibleStartedAt,
        "audible_deadline_at" to audibleDeadlineAt,
        "quiet_since" to quietSince,
        "elapsed_deadline_millis" to elapsedDeadlineMillis,
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
                "finalize_outcome" to it.finalizeOutcome,
            )
        },
    )

    @Suppress("UNCHECKED_CAST")
    private fun objectMap(value: Any?): Map<String, Any?> = value as? Map<String, Any?> ?: error("Ring state object is malformed.")
    private fun string(value: Any?): String = (value as? String)?.takeIf { it.isNotBlank() } ?: error("Ring state string is malformed.")
    private fun nullableString(value: Any?): String? = if (value == null) null else string(value)
    private fun bool(value: Any?): Boolean = value as? Boolean ?: error("Ring state boolean is malformed.")
    private fun number(value: Any?): Long = nullableNumber(value) ?: error("Ring state integer is malformed.")
    private fun nullableNumber(value: Any?): Long? = when (value) {
        null -> null
        is Byte -> value.toLong()
        is Short -> value.toLong()
        is Int -> value.toLong()
        is Long -> value
        else -> error("Ring state integer is malformed.")
    }

    companion object {
        private const val PreferencesName = "excellent_calendar_ring_v1"
        private const val KeyState = "versioned_state"
        private const val SchemaVersion = 1L
    }
}
