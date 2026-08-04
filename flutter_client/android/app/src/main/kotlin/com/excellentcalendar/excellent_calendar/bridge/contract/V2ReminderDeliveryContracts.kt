package com.excellentcalendar.excellent_calendar.bridge.contract

data class V2ReminderItem(
    val reminderId: String,
    val remindAt: String,
    val status: String,
) {
    val isTerminal: Boolean get() = status in TerminalStatuses

    private companion object {
        val TerminalStatuses = setOf("sent", "failed", "cancelled", "expired")
    }
}

data class V2SchedulableCursor(val remindAt: String, val reminderId: String) {
    fun toMap(): Map<String, Any?> = linkedMapOf("remind_at" to remindAt, "reminder_id" to reminderId)
}

data class V2SchedulableBatch(
    val reminders: List<V2ReminderItem>,
    val nextCursor: V2SchedulableCursor?,
) {
    companion object {
        fun fromData(data: Any?): V2SchedulableBatch {
            val map = objectMap(data, "SchedulableReminderListResponse")
            requireExactFields(map, setOf("items", "selected_count", "has_more", "next_cursor", "unsupported_reminder_ids"), "SchedulableReminderListResponse")
            val items = map["items"] as? List<*>
                ?: throw NativeContractViolation("items must be an array.", "data.items")
            val reminders = items.mapIndexed { index, item -> reminderItem(item, "data.items[$index]") }
            val selected = integerValue(map["selected_count"])?.toInt()
                ?: throw NativeContractViolation("selected_count must be integer.", "data.selected_count")
            if (selected !in 0..500 || selected != reminders.size) throw NativeContractViolation("selected_count does not match items.", "data.selected_count")
            if (reminders.size > 500) throw NativeContractViolation("items exceeds 500.", "data.items")
            val hasMore = map["has_more"] as? Boolean
                ?: throw NativeContractViolation("has_more must be boolean.", "data.has_more")
            val cursor = cursor(map["next_cursor"])
            if (hasMore != (cursor != null)) throw NativeContractViolation("next_cursor must match has_more.", "data.next_cursor")
            val unsupported = map["unsupported_reminder_ids"]
            if (unsupported !is List<*> || unsupported.any { it !is String || it.isBlank() } || unsupported.distinct().size != unsupported.size) {
                throw NativeContractViolation("unsupported_reminder_ids must be a unique string array.", "data.unsupported_reminder_ids")
            }
            return V2SchedulableBatch(reminders, cursor)
        }

        private fun cursor(value: Any?): V2SchedulableCursor? {
            if (value == null) return null
            val map = objectMap(value, "SchedulableReminderCursor")
            requireExactFields(map, setOf("remind_at", "reminder_id"), "SchedulableReminderCursor")
            return V2SchedulableCursor(requiredString(map, "remind_at", "SchedulableReminderCursor"), requiredString(map, "reminder_id", "SchedulableReminderCursor"))
        }
    }
}

data class V2PreparedDelivery(
    val notification: Map<String, Any?>,
    val tapPayload: Map<String, Any?>,
    val idempotentReplay: Boolean,
) {
    val deliveryId: String get() = requiredString(notification, "delivery_id", "NotificationResponse")
    val attemptId: String get() = requiredString(notification, "delivery_attempt_id", "NotificationResponse")
    val title: String get() = requiredString(notification, "title", "NotificationResponse")
    val body: String? get() = notification["body"] as String?

    companion object {
        fun fromData(data: Any?): V2PreparedDelivery {
            val map = objectMap(data, "PrepareDeliveryResponse")
            requireExactFields(map, setOf("notification", "tap_payload", "idempotent_replay"), "PrepareDeliveryResponse")
            val notification = notificationMap(map["notification"])
            val payload = preparedPayloadMap(map["tap_payload"])
            val replay = map["idempotent_replay"] as? Boolean
                ?: throw NativeContractViolation("idempotent_replay must be boolean.", "data.idempotent_replay")
            if (payload["delivery_id"] != notification["delivery_id"] || payload["delivery_attempt_id"] != notification["delivery_attempt_id"]) {
                throw NativeContractViolation("Prepared payload identity does not match Notification.", "data.tap_payload.delivery_id")
            }
            return V2PreparedDelivery(notification, payload, replay)
        }
    }
}

data class V2FinalizeDelivery(
    val notification: Map<String, Any?>,
    val recoveryBatch: Map<String, Any?>?,
    val idempotentReplay: Boolean,
) {
    val recoveryCompleted: Boolean get() = recoveryBatch?.get("status") == "completed"

    companion object {
        fun fromData(data: Any?): V2FinalizeDelivery {
            val map = objectMap(data, "FinalizeDeliveryResponse")
            requireExactFields(map, setOf("notification", "reminder", "successor", "recovery_batch", "idempotent_replay"), "FinalizeDeliveryResponse")
            val notification = notificationMap(map["notification"])
            map["reminder"]?.let(V2ResponseContracts::reminder)
            map["successor"]?.let(V2ResponseContracts::reminder)
            val batch = map["recovery_batch"]?.let(::recoveryBatchMap)
            val replay = map["idempotent_replay"] as? Boolean
                ?: throw NativeContractViolation("idempotent_replay must be boolean.", "data.idempotent_replay")
            if (notification["kind"] == "recovery_summary") {
                if (map["reminder"] != null || map["successor"] != null || batch == null) {
                    throw NativeContractViolation("Recovery summary finalize shape is invalid.", "data.notification.kind")
                }
            } else if (map["reminder"] == null) {
                throw NativeContractViolation("Reminder delivery must return its Reminder.", "data.reminder")
            }
            val belongsToRecovery = notification["recovery_batch_id"] is String ||
                notification["resolved_by_recovery_batch_id"] is String
            if (belongsToRecovery != (batch != null)) {
                throw NativeContractViolation("recovery_batch must match Notification recovery identity.", "data.recovery_batch")
            }
            return V2FinalizeDelivery(notification, batch, replay)
        }
    }
}

data class V2RecoveryResolution(
    val deliveryAttemptId: String,
    val deliveryId: String,
    val reminderId: String,
    val resolution: String,
    val replacementDeliveryId: String?,
)

data class V2RecoveryPlan(
    val batch: Map<String, Any?>,
    val detailReminders: List<V2ReminderItem>,
    val resolutions: List<V2RecoveryResolution>,
) {
    val batchId: String get() = requiredString(batch, "recovery_batch_id", "ReminderRecoveryBatchResponse")
    val status: String get() = requiredString(batch, "status", "ReminderRecoveryBatchResponse")
    val needsSummary: Boolean get() = batch["summary_delivery_id"] is String

    companion object {
        fun fromData(data: Any?): V2RecoveryPlan {
            val map = objectMap(data, "PlanRecoveryResponse")
            requireExactFields(map, setOf("batch", "detail_reminders", "prepared_attempt_resolutions", "idempotent_replay"), "PlanRecoveryResponse")
            val batch = recoveryBatchMap(map["batch"])
            val details = (map["detail_reminders"] as? List<*>)?.mapIndexed { index, item -> reminderItem(item, "data.detail_reminders[$index]") }
                ?: throw NativeContractViolation("detail_reminders must be an array.", "data.detail_reminders")
            if (details.size > 20) throw NativeContractViolation("detail_reminders exceeds 20.", "data.detail_reminders")
            if (batch["detail_reminder_ids"] != details.map(V2ReminderItem::reminderId)) {
                throw NativeContractViolation("detail_reminders must match batch detail_reminder_ids in order.", "data.detail_reminders")
            }
            val resolutions = (map["prepared_attempt_resolutions"] as? List<*>)?.mapIndexed { index, item ->
                val value = objectMap(item, "PreparedAttemptRecoveryResolution")
                requireExactFields(
                    value,
                    setOf("delivery_attempt_id", "delivery_id", "reminder_id", "resolution", "replacement_delivery_id"),
                    "PreparedAttemptRecoveryResolution",
                )
                val resolution = requiredString(value, "resolution", "PreparedAttemptRecoveryResolution")
                if (resolution !in setOf("adopted_detail", "abandoned_to_summary", "abandoned_outside_window")) {
                    throw NativeContractViolation("Unsupported recovery resolution.", "data.prepared_attempt_resolutions[$index].resolution")
                }
                val replacement = nullableString(value, "replacement_delivery_id", "PreparedAttemptRecoveryResolution")
                if ((resolution == "adopted_detail") != (replacement == null)) {
                    throw NativeContractViolation("replacement_delivery_id does not match recovery resolution.", "data.prepared_attempt_resolutions[$index].replacement_delivery_id")
                }
                V2RecoveryResolution(
                    deliveryAttemptId = requiredString(value, "delivery_attempt_id", "PreparedAttemptRecoveryResolution"),
                    deliveryId = requiredString(value, "delivery_id", "PreparedAttemptRecoveryResolution"),
                    reminderId = requiredString(value, "reminder_id", "PreparedAttemptRecoveryResolution"),
                    resolution = resolution,
                    replacementDeliveryId = replacement,
                )
            } ?: throw NativeContractViolation("prepared_attempt_resolutions must be an array.", "data.prepared_attempt_resolutions")
            if (map["idempotent_replay"] !is Boolean) {
                throw NativeContractViolation("idempotent_replay must be boolean.", "data.idempotent_replay")
            }
            return V2RecoveryPlan(batch, details, resolutions)
        }
    }
}

private val NotificationFields = setOf(
    "notification_id", "delivery_id", "delivery_attempt_id", "kind", "reminder_id", "recovery_batch_id",
    "resolved_by_recovery_batch_id", "target_type", "target_id", "occurrence_key", "method", "title", "body",
    "planned_at", "status", "failure_class", "error_code", "abandon_reason", "prepared_at", "finalized_at",
    "sent_at", "created_at", "updated_at",
)

private fun notificationMap(value: Any?): Map<String, Any?> {
    val map = objectMap(value, "NotificationResponse")
    requireExactFields(map, NotificationFields, "NotificationResponse")
    listOf("notification_id", "delivery_id", "delivery_attempt_id", "kind", "target_type", "target_id", "method", "title", "planned_at", "status", "prepared_at", "created_at", "updated_at")
        .forEach { requiredString(map, it, "NotificationResponse") }
    listOf("reminder_id", "recovery_batch_id", "resolved_by_recovery_batch_id", "occurrence_key", "body", "failure_class", "error_code", "abandon_reason", "finalized_at", "sent_at")
        .forEach { nullableString(map, it, "NotificationResponse") }
    val kind = map["kind"] as String
    val status = map["status"] as String
    if (kind !in setOf("reminder", "recovery_summary") || map["method"] !in setOf("ring", "popup", "wechat") || status !in setOf("prepared", "sent", "failed", "abandoned")) {
        throw NativeContractViolation("Notification enum value is invalid.", "NotificationResponse")
    }
    if ((kind == "reminder") != (map["reminder_id"] is String) || (kind == "recovery_summary") != (map["recovery_batch_id"] is String)) {
        throw NativeContractViolation("Notification kind identity is invalid.", "NotificationResponse.kind")
    }
    if (map["recovery_batch_id"] != null && map["resolved_by_recovery_batch_id"] != null) {
        throw NativeContractViolation("Notification recovery identities are mutually exclusive.", "NotificationResponse.recovery_batch_id")
    }
    validateNotificationStatus(map, status)
    return map
}

private fun reminderItem(value: Any?, parent: String): V2ReminderItem {
    val map = objectMap(value, parent)
    V2ResponseContracts.reminder(map)
    return V2ReminderItem(
        reminderId = requiredString(map, "reminder_id", parent),
        remindAt = requiredString(map, "remind_at", parent),
        status = requiredString(map, "status", parent),
    )
}

private val RecoveryBatchFields = setOf(
    "recovery_batch_id", "recovery_request_id", "trigger_source", "started_at", "window_start_at",
    "detail_reminder_ids", "summary_reminder_ids", "older_skipped_occurrence_count",
    "older_skipped_reminder_count", "window_overflow_count", "summary_delivery_id", "status", "completed_at",
)

private fun recoveryBatchMap(value: Any?): Map<String, Any?> {
    val map = objectMap(value, "ReminderRecoveryBatchResponse")
    requireExactFields(map, RecoveryBatchFields, "ReminderRecoveryBatchResponse")
    listOf("recovery_batch_id", "recovery_request_id", "started_at", "window_start_at")
        .forEach { requiredString(map, it, "ReminderRecoveryBatchResponse") }
    val trigger = requiredString(map, "trigger_source", "ReminderRecoveryBatchResponse")
    val status = requiredString(map, "status", "ReminderRecoveryBatchResponse")
    if (trigger !in setOf("app_start", "device_boot", "alarm_reconcile") || status !in setOf("in_progress", "completed")) {
        throw NativeContractViolation("Recovery batch enum value is invalid.", "ReminderRecoveryBatchResponse")
    }
    val details = stringList(map, "detail_reminder_ids", "ReminderRecoveryBatchResponse", maximum = 20)
    val summaries = stringList(map, "summary_reminder_ids", "ReminderRecoveryBatchResponse")
    val olderOccurrences = nonNegativeInteger(map, "older_skipped_occurrence_count", "ReminderRecoveryBatchResponse")
    val olderReminders = nonNegativeInteger(map, "older_skipped_reminder_count", "ReminderRecoveryBatchResponse")
    val overflow = nonNegativeInteger(map, "window_overflow_count", "ReminderRecoveryBatchResponse")
    if (overflow != summaries.size.toLong()) {
        throw NativeContractViolation("window_overflow_count must match summary_reminder_ids.", "ReminderRecoveryBatchResponse.window_overflow_count")
    }
    val summaryDeliveryId = nullableString(map, "summary_delivery_id", "ReminderRecoveryBatchResponse")
    val requiresSummary = summaries.isNotEmpty() || olderOccurrences > 0 || olderReminders > 0
    if (requiresSummary != (summaryDeliveryId != null)) {
        throw NativeContractViolation("summary_delivery_id does not match recovery counts.", "ReminderRecoveryBatchResponse.summary_delivery_id")
    }
    val completedAt = nullableString(map, "completed_at", "ReminderRecoveryBatchResponse")
    if ((status == "completed") != (completedAt != null)) {
        throw NativeContractViolation("completed_at does not match recovery status.", "ReminderRecoveryBatchResponse.completed_at")
    }
    if (details.toSet().intersect(summaries.toSet()).isNotEmpty()) {
        throw NativeContractViolation("Recovery detail and summary IDs must be disjoint.", "ReminderRecoveryBatchResponse")
    }
    return map
}

private fun preparedPayloadMap(value: Any?): Map<String, Any?> {
    val map = objectMap(value, "PreparedNotificationPayload")
    val fields = setOf("notification_id", "delivery_id", "delivery_attempt_id", "kind", "reminder_id", "recovery_batch_id", "target_type", "target_id", "occurrence_key", "route")
    requireExactFields(map, fields, "PreparedNotificationPayload")
    listOf("notification_id", "delivery_id", "delivery_attempt_id", "kind", "target_type", "target_id")
        .forEach { requiredString(map, it, "PreparedNotificationPayload") }
    listOf("reminder_id", "recovery_batch_id", "occurrence_key", "route")
        .forEach { nullableString(map, it, "PreparedNotificationPayload") }
    val kind = map["kind"]
    if (kind !in setOf("reminder", "recovery_summary") || map["target_type"] !in setOf("event", "habit", "anniversary", "reminder_recovery_batch")) {
        throw NativeContractViolation("Prepared payload enum value is invalid.", "PreparedNotificationPayload")
    }
    if ((kind == "reminder") != (map["reminder_id"] is String) || (kind == "recovery_summary") != (map["recovery_batch_id"] is String)) {
        throw NativeContractViolation("Prepared payload kind identity is invalid.", "PreparedNotificationPayload.kind")
    }
    return map
}

private fun validateNotificationStatus(map: Map<String, Any?>, status: String) {
    val failureClass = map["failure_class"]
    val errorCode = map["error_code"]
    val abandonReason = map["abandon_reason"]
    val finalizedAt = map["finalized_at"]
    val sentAt = map["sent_at"]
    val valid = when (status) {
        "prepared" -> failureClass == null && errorCode == null && abandonReason == null && finalizedAt == null && sentAt == null
        "sent" -> failureClass == null && errorCode == null && abandonReason == null && finalizedAt is String && sentAt is String
        "failed" -> failureClass in setOf("retryable", "permanent") && errorCode is String && errorCode.isNotBlank() && abandonReason == null && finalizedAt is String && sentAt == null
        "abandoned" -> map["resolved_by_recovery_batch_id"] is String && failureClass == null && errorCode == null && abandonReason in setOf("recovery_window_elapsed", "recovery_summary_superseded") && finalizedAt is String && sentAt == null
        else -> false
    }
    if (!valid) throw NativeContractViolation("Notification status fields are inconsistent.", "NotificationResponse.status")
}

private fun requireExactFields(map: Map<String, Any?>, fields: Set<String>, parent: String) {
    ContractValidators.rejectUnknownFields(map, fields, parent)
    fields.firstOrNull { !map.containsKey(it) }?.let {
        throw NativeContractViolation("$parent.$it is required.", "$parent.$it")
    }
}

private fun stringList(map: Map<String, Any?>, key: String, parent: String, maximum: Int? = null): List<String> {
    val raw = map[key] as? List<*> ?: throw NativeContractViolation("$parent.$key must be an array.", "$parent.$key")
    if (raw.any { it !is String || it.isBlank() } || raw.distinct().size != raw.size || (maximum != null && raw.size > maximum)) {
        throw NativeContractViolation("$parent.$key must be a bounded unique string array.", "$parent.$key")
    }
    @Suppress("UNCHECKED_CAST")
    return raw as List<String>
}

private fun nullableString(map: Map<String, Any?>, key: String, parent: String): String? {
    val value = map[key] ?: return null
    if (value !is String || value.isBlank()) throw NativeContractViolation("$parent.$key must be a non-empty string or null.", "$parent.$key")
    return value
}

private fun nonNegativeInteger(map: Map<String, Any?>, key: String, parent: String): Long {
    val value = integerValue(map[key]) ?: throw NativeContractViolation("$parent.$key must be integer.", "$parent.$key")
    if (value < 0) throw NativeContractViolation("$parent.$key must be non-negative.", "$parent.$key")
    return value
}

private fun integerValue(value: Any?): Long? = when (value) {
    is Byte -> value.toLong()
    is Short -> value.toLong()
    is Int -> value.toLong()
    is Long -> value
    else -> null
}

@Suppress("UNCHECKED_CAST")
private fun objectMap(value: Any?, parent: String): Map<String, Any?> =
    value as? Map<String, Any?> ?: throw NativeContractViolation("$parent must be an object.", parent)

private fun requiredString(map: Map<String, Any?>, key: String, parent: String): String =
    (map[key] as? String)?.takeIf { it.isNotBlank() }
        ?: throw NativeContractViolation("$parent.$key must be a non-empty string.", "$parent.$key")
