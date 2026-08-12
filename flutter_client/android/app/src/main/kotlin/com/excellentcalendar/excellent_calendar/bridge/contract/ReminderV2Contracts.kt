package com.excellentcalendar.excellent_calendar.bridge.contract

/** Request and response validation owned by the Reminder module. */
internal object ReminderV2Contracts {
    private val responseFields = setOf(
        "reminder_id", "target_type", "target_id", "recurrence_revision", "occurrence_key", "occurrence_start_at",
        "remind_at", "advance_minutes", "methods", "message", "is_enabled", "status", "scheduled_at",
        "last_triggered_at", "failure_reason", "last_cancellation_reason", "last_cancelled_at", "expiration_reason",
        "expired_at", "reactivated_at", "reactivation_count", "created_at", "updated_at", "deleted_at",
    )

    fun create(arguments: Any?): V2JsonRequest =
        V2ContractPrimitives.request(arguments, "CreateReminderRequest") { map ->
            val allowed = setOf(
                "target_type", "target_id", "remind_at", "advance_minutes", "methods", "message", "is_enabled", "source",
            )
            ContractValidators.rejectUnknownFields(map, allowed, "CreateReminderRequest")
            V2ContractPrimitives.requireFields(
                map,
                setOf("target_type", "target_id", "methods", "is_enabled", "source"),
                "CreateReminderRequest",
            )
            validateOrdinaryReminder(map, "CreateReminderRequest", requireTime = true)
        }

    fun update(arguments: Any?): V2JsonRequest =
        V2ContractPrimitives.request(arguments, "UpdateReminderRequest") { map ->
            val allowed = setOf(
                "reminder_id", "target_type", "target_id", "remind_at", "advance_minutes", "methods", "message", "source",
            )
            ContractValidators.rejectUnknownFields(map, allowed, "UpdateReminderRequest")
            ContractValidators.requireString(map, "reminder_id", "UpdateReminderRequest", nonEmpty = true)
            if (map.containsKey("methods")) validateMethods(map, "UpdateReminderRequest")
            if (map.containsKey("remind_at") && map["remind_at"] != null && map["remind_at"] !is String) {
                throw NativeContractViolation("Invalid remind_at.", "UpdateReminderRequest.remind_at")
            }
            V2ContractPrimitives.nullableInteger(map, "advance_minutes", "UpdateReminderRequest")
        }

    fun cancel(arguments: Any?): V2JsonRequest =
        V2ContractPrimitives.request(arguments, "CancelReminderRequest") { map ->
            ContractValidators.rejectUnknownFields(map, setOf("reminder_id"), "CancelReminderRequest")
            ContractValidators.requireString(map, "reminder_id", "CancelReminderRequest", nonEmpty = true)
        }

    fun list(arguments: Any?): V2JsonRequest =
        V2ContractPrimitives.request(arguments, "ListRemindersRequest") { map ->
            val allowed = setOf(
                "target_type", "target_id", "recurrence_revision", "occurrence_key", "remind_at_from", "remind_at_to",
                "methods", "status", "is_enabled", "include_deleted", "pagination", "sort_by", "sort_direction",
            )
            ContractValidators.rejectUnknownFields(map, allowed, "ListRemindersRequest")
            ContractValidators.optionalStringArray(map, "methods", "ListRemindersRequest", ContractEnums.ReminderMethods)
            ContractValidators.optionalStringArray(map, "status", "ListRemindersRequest", ContractEnums.ReminderStatus)
            ContractValidators.optionalEnum(map, "sort_direction", "ListRemindersRequest", ContractEnums.SortDirection)
        }

    fun validateDraft(map: Map<String, Any?>, recurring: Boolean, parent: String) {
        val allowed = if (recurring) {
            setOf("target_type", "target_id", "advance_minutes", "methods", "message", "is_enabled", "source")
        } else {
            setOf("target_type", "target_id", "remind_at", "advance_minutes", "methods", "message", "is_enabled", "source")
        }
        ContractValidators.rejectUnknownFields(map, allowed, parent)
        if (recurring) {
            V2ContractPrimitives.requireFields(
                map,
                setOf("target_type", "advance_minutes", "methods", "message", "is_enabled", "source"),
                parent,
            )
            val methods = map["methods"]
            if (map["target_type"] != "event" || methods != listOf("popup") || map["is_enabled"] != true) {
                throw NativeContractViolation(
                    "Recurring reminder templates support enabled popup Event reminders only.",
                    parent,
                )
            }
            V2ContractPrimitives.positiveInteger(map, "advance_minutes", parent, minimum = 0)
            V2ContractPrimitives.nullableNonBlankString(map, "target_id", parent)
            V2ContractPrimitives.nullableString(map, "message", parent)
            ContractValidators.requireEnum(map, "source", parent, ContractEnums.ReminderSource)
        } else {
            V2ContractPrimitives.requireFields(
                map,
                setOf("target_type", "methods", "is_enabled", "source"),
                parent,
            )
            ContractValidators.requireEnum(map, "target_type", parent, setOf("event", "anniversary"))
            V2ContractPrimitives.nullableNonBlankString(map, "target_id", parent)
            V2ContractPrimitives.nullableString(map, "message", parent)
            ContractValidators.requireBoolean(map, "is_enabled", parent)
            if (map["is_enabled"] != true) {
                throw NativeContractViolation("$parent.is_enabled must be true.", "$parent.is_enabled")
            }
            ContractValidators.requireEnum(map, "source", parent, ContractEnums.ReminderSource)
            validateMethods(map, parent)
            validateExactlyOneReminderTime(map, parent)
        }
    }

    fun response(data: Any?) {
        val map = V2ContractPrimitives.objectMap(data, "ReminderResponse")
        V2ContractPrimitives.requireExactFields(map, responseFields, "ReminderResponse")
        ContractValidators.requireEnum(
            map,
            "status",
            "ReminderResponse",
            setOf("pending", "scheduled", "sent", "failed", "cancelled", "expired"),
        )
        ContractValidators.requireString(map, "reminder_id", "ReminderResponse", nonEmpty = true)
        ContractValidators.requireString(map, "remind_at", "ReminderResponse", nonEmpty = true)
    }

    fun listResponse(data: Any?) {
        val map = V2ContractPrimitives.objectMap(data, "ReminderListResponse")
        V2ContractPrimitives.requireExactFields(map, setOf("items", "pagination"), "ReminderListResponse")
        val items = map["items"] as? List<*>
            ?: throw NativeContractViolation("items must be an array.", "data.items")
        items.forEach(::response)
        V2ContractPrimitives.objectMap(map["pagination"], "PaginationResponse")
    }

    private fun validateOrdinaryReminder(map: Map<String, Any?>, parent: String, requireTime: Boolean) {
        ContractValidators.requireEnum(map, "target_type", parent, ContractEnums.ReminderTargetType)
        ContractValidators.requireString(map, "target_id", parent, nonEmpty = true)
        ContractValidators.requireBoolean(map, "is_enabled", parent)
        if (map["is_enabled"] != true) {
            throw NativeContractViolation("$parent.is_enabled must be true.", "$parent.is_enabled")
        }
        ContractValidators.requireEnum(map, "source", parent, ContractEnums.ReminderSource)
        validateMethods(map, parent)
        if (requireTime) validateExactlyOneReminderTime(map, parent)
    }

    private fun validateMethods(map: Map<String, Any?>, parent: String) {
        val methods = map["methods"]
        if (
            methods !is List<*> ||
            methods.isEmpty() ||
            methods.any { it !is String || it !in ContractEnums.ReminderMethods } ||
            methods.distinct().size != methods.size
        ) {
            throw NativeContractViolation("$parent.methods is invalid.", "$parent.methods")
        }
    }

    private fun validateExactlyOneReminderTime(map: Map<String, Any?>, parent: String) {
        val remindAt = map["remind_at"]
        val advance = map["advance_minutes"]
        val valid = (
            map.containsKey("remind_at") && remindAt is String && remindAt.isNotBlank() && advance == null
            ) || (
            map.containsKey("advance_minutes") &&
                remindAt == null &&
                V2ContractPrimitives.integerValue(advance)?.let { it >= 0 } == true
            )
        if (!valid) {
            throw NativeContractViolation(
                "$parent must contain exactly one reminder time form.",
                "$parent.remind_at",
            )
        }
    }
}
