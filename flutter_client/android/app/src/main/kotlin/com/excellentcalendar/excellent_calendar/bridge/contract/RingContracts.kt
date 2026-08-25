package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import java.util.UUID

data class RingRevisionRequest(val expectedSettingsRevision: Long)

data class UpdateRingSettingsContract(
    val expectedSettingsRevision: Long,
    val strongReminderEnabled: Boolean,
)

data class RingTestContract(
    val action: String,
    val expectedSettingsRevision: Long,
)

data class ActiveRingItemsContract(
    val runtimeInstanceId: String,
    val sessionId: String,
    val expectedSessionRevision: Long,
    val deliveryIds: List<String>,
)

data class CompleteRingItemContract(
    val runtimeInstanceId: String,
    val sessionId: String,
    val expectedSessionRevision: Long,
    val deliveryId: String,
)

object RingRequestContracts {
    fun settingsRevision(arguments: Any?): RingRevisionRequest {
        val map = map(arguments, "PickRingtoneRequest")
        exact(map, setOf("expected_settings_revision"), "PickRingtoneRequest")
        return RingRevisionRequest(revision(map, "expected_settings_revision", "PickRingtoneRequest", allowZero = true))
    }

    fun updateSettings(arguments: Any?): UpdateRingSettingsContract {
        val parent = "UpdateRingSettingsRequest"
        val map = map(arguments, parent)
        exact(map, setOf("expected_settings_revision", "strong_reminder_enabled"), parent)
        val enabled = map["strong_reminder_enabled"] as? Boolean
            ?: throw NativeContractViolation("$parent.strong_reminder_enabled must be boolean.", "$parent.strong_reminder_enabled")
        return UpdateRingSettingsContract(revision(map, "expected_settings_revision", parent, allowZero = true), enabled)
    }

    fun test(arguments: Any?): RingTestContract {
        val parent = "RingTestRequest"
        val map = map(arguments, parent)
        exact(map, setOf("action", "expected_settings_revision"), parent)
        val action = map["action"] as? String
        if (action !in setOf("start", "stop")) {
            throw NativeContractViolation("$parent.action is invalid.", "$parent.action")
        }
        return RingTestContract(action!!, revision(map, "expected_settings_revision", parent, allowZero = true))
    }

    fun activeItems(arguments: Any?): ActiveRingItemsContract {
        val parent = "ActiveRingItemsRequest"
        val map = map(arguments, parent)
        exact(map, setOf("runtime_instance_id", "session_id", "expected_session_revision", "delivery_ids"), parent)
        val ids = map["delivery_ids"] as? List<*>
            ?: throw NativeContractViolation("$parent.delivery_ids must be an array.", "$parent.delivery_ids")
        if (ids.isEmpty() || ids.any { it !is String || !isUuid(it) } || ids.distinct().size != ids.size) {
            throw NativeContractViolation("$parent.delivery_ids must contain unique UUIDs.", "$parent.delivery_ids")
        }
        @Suppress("UNCHECKED_CAST")
        return ActiveRingItemsContract(
            uuid(map, "runtime_instance_id", parent),
            uuid(map, "session_id", parent),
            revision(map, "expected_session_revision", parent, allowZero = false),
            ids as List<String>,
        )
    }

    fun completeItem(arguments: Any?): CompleteRingItemContract {
        val parent = "CompleteRingItemRequest"
        val map = map(arguments, parent)
        exact(map, setOf("runtime_instance_id", "session_id", "expected_session_revision", "delivery_id"), parent)
        return CompleteRingItemContract(
            uuid(map, "runtime_instance_id", parent),
            uuid(map, "session_id", parent),
            revision(map, "expected_session_revision", parent, allowZero = false),
            uuid(map, "delivery_id", parent),
        )
    }

    private fun map(arguments: Any?, parent: String): Map<String, Any?> = try {
        NativeContractJsonCodec.normalizeMap(arguments)
    } catch (error: IllegalArgumentException) {
        throw NativeContractViolation("$parent must be an object.", parent, error)
    }

    private fun exact(map: Map<String, Any?>, fields: Set<String>, parent: String) {
        ContractValidators.rejectUnknownFields(map, fields, parent)
        fields.firstOrNull { !map.containsKey(it) }?.let {
            throw NativeContractViolation("$parent.$it is required.", "$parent.$it")
        }
    }

    private fun uuid(map: Map<String, Any?>, key: String, parent: String): String {
        val value = map[key] as? String
        if (value == null || !isUuid(value)) {
            throw NativeContractViolation("$parent.$key must be a UUID.", "$parent.$key")
        }
        return value
    }

    private fun revision(map: Map<String, Any?>, key: String, parent: String, allowZero: Boolean): Long {
        val value = when (val raw = map[key]) {
            is Byte -> raw.toLong()
            is Short -> raw.toLong()
            is Int -> raw.toLong()
            is Long -> raw
            else -> null
        }
        val minimum = if (allowZero) 0L else 1L
        if (value == null || value < minimum || value > MaxSafeInteger) {
            throw NativeContractViolation("$parent.$key is out of range.", "$parent.$key")
        }
        return value
    }

    private fun isUuid(value: Any?): Boolean = try {
        UUID.fromString(value as? String)
        true
    } catch (_: Exception) {
        false
    }

    private const val MaxSafeInteger = 9_007_199_254_740_991L
}
