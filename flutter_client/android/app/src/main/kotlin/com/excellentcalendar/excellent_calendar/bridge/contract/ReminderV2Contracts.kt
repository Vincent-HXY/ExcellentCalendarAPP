package com.excellentcalendar.excellent_calendar.bridge.contract

/** Request and response validation owned by the Reminder module. */
internal object ReminderV2Contracts {
    private val responseFields = setOf(
        "reminder_id", "target_type", "target_id", "recurrence_revision", "occurrence_key", "occurrence_start_at",
        "template_key", "occurrence_date", "advance_days", "local_time", "timezone_mode", "fulfillment_delivery_id",
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
        ContractValidators.requireEnum(map, "target_type", "ReminderResponse", setOf("event", "habit", "anniversary"))
        ContractValidators.requireString(map, "target_id", "ReminderResponse", nonEmpty = true)
        ContractValidators.requireString(map, "remind_at", "ReminderResponse", nonEmpty = true)
        val methods = map["methods"] as? List<*>
        if (methods == null || methods.size != 1 || methods.single() !in setOf("ring", "popup")) {
            throw NativeContractViolation("ReminderResponse.methods must contain exactly one supported method.", "ReminderResponse.methods")
        }
        validateTargetShape(map, methods.single() as String)
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

    private fun validateTargetShape(map: Map<String, Any?>, method: String) {
        val parent = "ReminderResponse"
        val targetType = map["target_type"] as String
        val status = map["status"] as String
        val targetSpecificFields = listOf("template_key", "occurrence_date", "advance_days", "local_time", "timezone_mode")
        val anniversary = targetType == "anniversary"
        if (anniversary) {
            if (map["recurrence_revision"] != null || map["occurrence_start_at"] != null ||
                map["occurrence_key"] !is String || targetSpecificFields.any { map[it] == null } ||
                map["timezone_mode"] != "follow_device" || map["advance_minutes"] != null || method != "popup"
            ) {
                throw NativeContractViolation("$parent Anniversary target fields are inconsistent.", "$parent.target_type")
            }
            val advanceDays = V2ContractPrimitives.integerValue(map["advance_days"])
            if (advanceDays == null || advanceDays !in 0L..365L ||
                (map["local_time"] as? String)?.matches(Regex("^(?:[01][0-9]|2[0-3]):[0-5][0-9]$")) != true
            ) {
                throw NativeContractViolation("$parent Anniversary schedule projection is invalid.", "$parent.advance_days")
            }
            if ((status == "sent") != (map["fulfillment_delivery_id"] is String)) {
                throw NativeContractViolation("$parent.fulfillment_delivery_id must match sent status.", "$parent.fulfillment_delivery_id")
            }
        } else if (targetType == "habit") {
            val occurrenceDate = map["occurrence_date"] as? String
            val habitShape = map["recurrence_revision"] == null && map["occurrence_key"] is String &&
                map["occurrence_start_at"] == null && map["template_key"] is String &&
                occurrenceDate != null && runCatching { java.time.LocalDate.parse(occurrenceDate) }.isSuccess &&
                map["advance_days"] == null &&
                (map["local_time"] as? String)?.matches(Regex("^(?:[01][0-9]|2[0-3]):[0-5][0-9]$")) == true &&
                map["timezone_mode"] == "follow_device" && map["fulfillment_delivery_id"] == null &&
                map["advance_minutes"] == null && method == "popup" &&
                map["expiration_reason"] in setOf(null, "habit_occurrence_elapsed")
            if (!habitShape) {
                throw NativeContractViolation("$parent Habit target fields are inconsistent.", "$parent.target_type")
            }
        } else {
            if (targetSpecificFields.any { map[it] != null } || map["fulfillment_delivery_id"] != null) {
                throw NativeContractViolation("$parent Event target contains target-specific fields.", "$parent.target_type")
            }
            if (method == "ring" &&
                (targetType != "event" || map["recurrence_revision"] != null || map["occurrence_key"] != null ||
                    map["occurrence_start_at"] != null)
            ) {
                throw NativeContractViolation("$parent ring target fields are invalid.", "$parent.methods")
            }
        }
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
