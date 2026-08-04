package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec

object EmptyRequestContract {
    fun validate(arguments: Any?) {
        val map = normalizeArguments(arguments)
        ContractValidators.rejectUnknownFields(map, emptySet(), "EmptyRequest")
    }
}

data class RequestNotificationPermissionContract(
    val requestNotificationPermission: Boolean,
    val requestExactAlarmPermission: Boolean,
    val source: String,
) {
    companion object {
        private val Sources = setOf("app_startup", "settings_page", "reminder_creation", "manual_retry")

        fun fromMethodArguments(arguments: Any?): RequestNotificationPermissionContract {
            val map = normalizeArguments(arguments)
            val parent = "RequestNotificationPermissionRequest"
            ContractValidators.rejectUnknownFields(
                map,
                setOf("request_notification_permission", "request_exact_alarm_permission", "source"),
                parent,
            )
            ContractValidators.requireBoolean(map, "request_notification_permission", parent)
            ContractValidators.requireBoolean(map, "request_exact_alarm_permission", parent)
            ContractValidators.requireEnum(map, "source", parent, Sources)
            val notification = map["request_notification_permission"] as Boolean
            val exactAlarm = map["request_exact_alarm_permission"] as Boolean
            if (!notification && !exactAlarm) {
                throw NativeContractViolation(
                    "$parent must request at least one permission.",
                    parent,
                )
            }
            return RequestNotificationPermissionContract(notification, exactAlarm, map["source"] as String)
        }
    }
}

data class OpenNotificationSettingsContract(
    val settingsTarget: String,
) {
    companion object {
        fun fromMethodArguments(arguments: Any?): OpenNotificationSettingsContract {
            val map = normalizeArguments(arguments)
            val parent = "OpenNotificationSettingsRequest"
            ContractValidators.rejectUnknownFields(map, setOf("settings_target"), parent)
            ContractValidators.requireEnum(
                map,
                "settings_target",
                parent,
                setOf("notification", "exact_alarm", "application"),
            )
            return OpenNotificationSettingsContract(map["settings_target"] as String)
        }
    }
}

data class SchedulePendingRemindersContract(
    val fromAt: String,
    val toAt: String,
    val limit: Int,
    val forceReschedule: Boolean,
) {
    companion object {
        fun fromMethodArguments(arguments: Any?): SchedulePendingRemindersContract {
            val map = normalizeArguments(arguments)
            val parent = "SchedulePendingRemindersRequest"
            ContractValidators.rejectUnknownFields(
                map,
                setOf("from_at", "to_at", "limit", "force_reschedule"),
                parent,
            )
            ContractValidators.requireString(map, "from_at", parent, nonEmpty = true)
            ContractValidators.requireString(map, "to_at", parent, nonEmpty = true)
            ContractValidators.optionalInteger(map, "limit", parent)
            ContractValidators.optionalBoolean(map, "force_reschedule", parent)
            val limit = (map["limit"] as Number?)?.toInt() ?: 500
            if (limit !in 1..500) {
                throw NativeContractViolation("$parent.limit must be between 1 and 500.", "$parent.limit")
            }
            return SchedulePendingRemindersContract(
                fromAt = map["from_at"] as String,
                toAt = map["to_at"] as String,
                limit = limit,
                forceReschedule = map["force_reschedule"] as Boolean? ?: false,
            )
        }

        fun bootWindow(fromAt: String, toAt: String, limit: Int = 128): SchedulePendingRemindersContract {
            return SchedulePendingRemindersContract(fromAt, toAt, limit, forceReschedule = true)
        }
    }
}

data class SchedulableReminderBatch(
    val reminders: List<ReminderContract>,
    val hasMore: Boolean,
    val nextCursor: SchedulableReminderCursor?,
    val unsupportedReminderIds: List<String>,
) {
    companion object {
        fun fromData(data: Any?): SchedulableReminderBatch {
            if (data !is Map<*, *>) {
                throw NativeContractViolation("SchedulableReminderListResponse must be an object.", "data")
            }
            @Suppress("UNCHECKED_CAST")
            val map = data as Map<String, Any?>
            val parent = "SchedulableReminderListResponse"
            ContractValidators.rejectUnknownFields(
                map,
                setOf("items", "selected_count", "has_more", "next_cursor", "unsupported_reminder_ids"),
                parent,
            )
            val items = map["items"]
            if (items !is List<*>) {
                throw NativeContractViolation("$parent.items must be an array.", "$parent.items")
            }
            ContractValidators.requireInteger(map, "selected_count", parent)
            ContractValidators.requireBoolean(map, "has_more", parent)
            val nextCursor = SchedulableReminderCursor.fromData(map["next_cursor"])
            val hasMore = map["has_more"] as Boolean
            if (hasMore != (nextCursor != null)) {
                throw NativeContractViolation(
                    "$parent.next_cursor must be present exactly when has_more is true.",
                    "$parent.next_cursor",
                )
            }
            val unsupported = map["unsupported_reminder_ids"]
            if (unsupported !is List<*> || unsupported.any { it !is String || it.isBlank() }) {
                throw NativeContractViolation(
                    "$parent.unsupported_reminder_ids must be a string array.",
                    "$parent.unsupported_reminder_ids",
                )
            }
            val reminders = items.map { ReminderContract.fromData(it) }
            val selectedCount = (map["selected_count"] as Number).toInt()
            if (selectedCount != reminders.size) {
                throw NativeContractViolation("$parent.selected_count does not match items.", "$parent.selected_count")
            }
            @Suppress("UNCHECKED_CAST")
            return SchedulableReminderBatch(
                reminders = reminders,
                hasMore = hasMore,
                nextCursor = nextCursor,
                unsupportedReminderIds = unsupported as List<String>,
            )
        }
    }
}

data class SchedulableReminderCursor(val remindAt: String, val id: String) {
    fun toMap(): Map<String, Any?> = linkedMapOf("remind_at" to remindAt, "id" to id)

    companion object {
        fun fromData(data: Any?): SchedulableReminderCursor? {
            if (data == null) return null
            if (data !is Map<*, *>) {
                throw NativeContractViolation("SchedulableReminderCursor must be an object or null.", "next_cursor")
            }
            @Suppress("UNCHECKED_CAST")
            val map = data as Map<String, Any?>
            ContractValidators.rejectUnknownFields(map, setOf("remind_at", "id"), "SchedulableReminderCursor")
            ContractValidators.requireString(map, "remind_at", "SchedulableReminderCursor", nonEmpty = true)
            ContractValidators.requireString(map, "id", "SchedulableReminderCursor", nonEmpty = true)
            return SchedulableReminderCursor(map["remind_at"] as String, map["id"] as String)
        }
    }
}

object NotificationResponseContract {
    private val Fields = setOf(
        "id", "reminder_id", "target_type", "target_id", "method", "title", "body",
        "planned_at", "sent_at", "status", "failure_reason", "created_at", "updated_at",
    )

    fun validate(data: Any?) {
        if (data !is Map<*, *>) {
            throw NativeContractViolation("NotificationResponse must be an object.", "data")
        }
        @Suppress("UNCHECKED_CAST")
        validateMap(data as Map<String, Any?>, "NotificationResponse")
    }

    fun validateMap(map: Map<String, Any?>, parent: String) {
        ContractValidators.rejectUnknownFields(map, Fields, parent)
        ContractValidators.requireString(map, "id", parent, nonEmpty = true)
        ContractValidators.optionalString(map, "reminder_id", parent)
        ContractValidators.requireEnum(map, "target_type", parent, setOf("event", "habit", "anniversary", "dated_message"))
        ContractValidators.requireString(map, "target_id", parent, nonEmpty = true)
        ContractValidators.requireEnum(map, "method", parent, ContractEnums.ReminderMethods)
        ContractValidators.requireString(map, "title", parent, nonEmpty = true)
        ContractValidators.optionalString(map, "body", parent)
        ContractValidators.requireString(map, "planned_at", parent, nonEmpty = true)
        ContractValidators.optionalString(map, "sent_at", parent)
        ContractValidators.requireEnum(map, "status", parent, setOf("pending", "sent", "failed", "cancelled"))
        ContractValidators.optionalString(map, "failure_reason", parent)
        ContractValidators.requireString(map, "created_at", parent, nonEmpty = true)
        ContractValidators.requireString(map, "updated_at", parent, nonEmpty = true)
    }
}

object ConsumeReminderAfterDeliveryResponseContract {
    fun notification(data: Any?): Map<String, Any?> {
        if (data !is Map<*, *>) {
            throw NativeContractViolation("ConsumeReminderAfterDeliveryResponse must be an object.", "data")
        }
        @Suppress("UNCHECKED_CAST")
        val map = data as Map<String, Any?>
        ContractValidators.rejectUnknownFields(map, setOf("reminder", "notification"), "ConsumeReminderAfterDeliveryResponse")
        ReminderResponseContract.validate(map["reminder"])
        val notification = map["notification"]
        NotificationResponseContract.validate(notification)
        @Suppress("UNCHECKED_CAST")
        return notification as Map<String, Any?>
    }
}

object NotificationTapPayloadContract {
    fun normalize(value: Any?, openedAt: String): Map<String, Any?> {
        val map = normalizeArguments(value).toMutableMap()
        map["opened_at"] = openedAt
        val parent = "NotificationTapPayload"
        if (map.containsKey("delivery_id")) {
            ContractValidators.rejectUnknownFields(
                map,
                setOf(
                    "notification_id", "delivery_id", "delivery_attempt_id", "kind", "reminder_id",
                    "recovery_batch_id", "target_type", "target_id", "occurrence_key", "route", "opened_at",
                ),
                parent,
            )
            listOf("notification_id", "delivery_id", "delivery_attempt_id", "kind", "target_type", "target_id", "opened_at")
                .forEach { ContractValidators.requireString(map, it, parent, nonEmpty = true) }
            ContractValidators.optionalString(map, "reminder_id", parent)
            ContractValidators.optionalString(map, "recovery_batch_id", parent)
            ContractValidators.optionalString(map, "occurrence_key", parent)
            ContractValidators.optionalString(map, "route", parent)
            return map
        }
        ContractValidators.rejectUnknownFields(
            map,
            setOf("notification_id", "reminder_id", "target_type", "target_id", "route", "opened_at"),
            parent,
        )
        ContractValidators.requireString(map, "notification_id", parent, nonEmpty = true)
        if (!map.containsKey("reminder_id")) {
            throw NativeContractViolation("$parent.reminder_id is required.", "$parent.reminder_id")
        }
        ContractValidators.optionalString(map, "reminder_id", parent)
        ContractValidators.requireEnum(
            map,
            "target_type",
            parent,
            setOf("event", "habit", "anniversary", "dated_message"),
        )
        ContractValidators.requireString(map, "target_id", parent, nonEmpty = true)
        ContractValidators.optionalString(map, "route", parent)
        ContractValidators.requireString(map, "opened_at", parent, nonEmpty = true)
        return map
    }
}

private fun normalizeArguments(arguments: Any?): Map<String, Any?> {
    return try {
        NativeContractJsonCodec.normalizeMap(arguments)
    } catch (error: IllegalArgumentException) {
        throw NativeContractViolation(error.message ?: "Invalid MethodChannel arguments.", cause = error)
    }
}
