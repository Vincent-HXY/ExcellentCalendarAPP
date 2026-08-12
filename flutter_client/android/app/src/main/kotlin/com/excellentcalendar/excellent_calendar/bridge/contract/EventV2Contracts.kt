package com.excellentcalendar.excellent_calendar.bridge.contract

/** Request and response validation owned by the Event module. */
internal object EventV2Contracts {
    private val createFields = setOf(
        "title", "content", "start_at", "end_at", "start_date", "end_date", "is_all_day",
        "category_id", "importance", "location", "timezone", "source", "recurrence", "reminders",
    )
    private val updateFields = createFields + setOf("id", "expected_recurrence_revision")
    private val responseFields = setOf(
        "id", "title", "content", "start_at", "end_at", "start_date", "end_date", "is_all_day",
        "has_recurrence", "status", "completed_at", "recurrence_id", "recurrence_revision", "category_id",
        "importance", "location", "timezone", "source", "created_at", "updated_at", "deleted_at",
    )

    fun create(arguments: Any?): V2JsonRequest =
        V2ContractPrimitives.request(arguments, "CreateEventRequest") { map ->
            ContractValidators.rejectUnknownFields(map, createFields, "CreateEventRequest")
            V2ContractPrimitives.requireFields(
                map,
                setOf("title", "start_at", "end_at", "start_date", "end_date", "is_all_day", "timezone", "source"),
                "CreateEventRequest",
            )
            ContractValidators.requireString(map, "title", "CreateEventRequest", nonEmpty = true)
            V2ContractPrimitives.nullableString(map, "category_id", "CreateEventRequest")
            validateTimeGroup(map, "CreateEventRequest")
            validateRecurrenceAndReminders(map, "CreateEventRequest")
        }

    fun update(arguments: Any?): V2JsonRequest =
        V2ContractPrimitives.request(arguments, "UpdateEventRequest") { map ->
            ContractValidators.rejectUnknownFields(map, updateFields, "UpdateEventRequest")
            ContractValidators.requireString(map, "id", "UpdateEventRequest", nonEmpty = true)
            V2ContractPrimitives.nullableString(map, "category_id", "UpdateEventRequest")
            val timeFields = setOf("start_at", "end_at", "start_date", "end_date", "is_all_day", "timezone")
            if (map.keys.any { it in timeFields }) {
                V2ContractPrimitives.requireFields(map, timeFields, "UpdateEventRequest")
                validateTimeGroup(map, "UpdateEventRequest")
            }
            if (map.containsKey("recurrence") && map["recurrence"] == null) {
                throw NativeContractViolation(
                    "UpdateEventRequest.recurrence cannot be null.",
                    "UpdateEventRequest.recurrence",
                )
            }
            validateRecurrenceAndReminders(map, "UpdateEventRequest")
        }

    fun delete(arguments: Any?): V2JsonRequest =
        V2ContractPrimitives.request(arguments, "DeleteEventRequest") { map ->
            val allowed = setOf(
                "id", "delete_mode", "recurrence_delete_scope", "expected_recurrence_revision", "reason",
            )
            ContractValidators.rejectUnknownFields(map, allowed, "DeleteEventRequest")
            V2ContractPrimitives.requireFields(
                map,
                setOf("id", "delete_mode", "recurrence_delete_scope", "expected_recurrence_revision"),
                "DeleteEventRequest",
            )
            ContractValidators.requireString(map, "id", "DeleteEventRequest", nonEmpty = true)
            ContractValidators.requireEnum(map, "delete_mode", "DeleteEventRequest", setOf("soft", "hard"))
            val scope = map["recurrence_delete_scope"]
            if (scope != null && scope != "all_occurrences") {
                throw NativeContractViolation(
                    "Only all_occurrences is supported for recurring Event deletion.",
                    "DeleteEventRequest.recurrence_delete_scope",
                )
            }
            V2ContractPrimitives.nullableInteger(map, "expected_recurrence_revision", "DeleteEventRequest")
            ContractValidators.optionalString(map, "reason", "DeleteEventRequest")
        }

    fun id(arguments: Any?, parent: String): V2JsonRequest =
        V2ContractPrimitives.request(arguments, parent) { map ->
            ContractValidators.rejectUnknownFields(map, setOf("id"), parent)
            ContractValidators.requireString(map, "id", parent, nonEmpty = true)
        }

    fun search(arguments: Any?): V2JsonRequest =
        V2ContractPrimitives.request(arguments, "SearchEventRequest") { map ->
            val allowed = setOf(
                "keyword", "start_at_from", "start_at_to", "start_date_from", "start_date_to", "status",
                "category_ids", "importance", "location", "has_recurrence", "source", "include_deleted",
                "pagination", "sort_by", "sort_direction",
            )
            ContractValidators.rejectUnknownFields(map, allowed, "SearchEventRequest")
            ContractValidators.optionalStringArray(map, "status", "SearchEventRequest", ContractEnums.EventStatus)
            validateOptionalStringArray(map, "category_ids", "SearchEventRequest")
            ContractValidators.optionalStringArray(map, "importance", "SearchEventRequest", ContractEnums.Importance)
            ContractValidators.optionalStringArray(map, "source", "SearchEventRequest", ContractEnums.CreateEventSource)
            ContractValidators.optionalEnum(map, "sort_direction", "SearchEventRequest", ContractEnums.SortDirection)
        }

    fun complete(arguments: Any?): V2JsonRequest =
        V2ContractPrimitives.request(arguments, "CompleteEventRequest") { map ->
            ContractValidators.rejectUnknownFields(map, setOf("event_id", "source", "note"), "CompleteEventRequest")
            ContractValidators.requireString(map, "event_id", "CompleteEventRequest", nonEmpty = true)
            ContractValidators.requireEnum(map, "source", "CompleteEventRequest", ContractEnums.CompleteEventSource)
            ContractValidators.optionalString(map, "note", "CompleteEventRequest")
        }

    fun reopen(arguments: Any?): V2JsonRequest =
        V2ContractPrimitives.request(arguments, "ReopenEventRequest") { map ->
            ContractValidators.rejectUnknownFields(map, setOf("event_id"), "ReopenEventRequest")
            ContractValidators.requireString(map, "event_id", "ReopenEventRequest", nonEmpty = true)
        }

    fun response(data: Any?) {
        validateResponse(data)
    }

    private fun validateResponse(data: Any?): Map<String, Any?> {
        val map = V2ContractPrimitives.objectMap(data, "EventResponse")
        V2ContractPrimitives.requireExactFields(map, responseFields, "EventResponse")
        ContractValidators.requireBoolean(map, "is_all_day", "EventResponse")
        ContractValidators.requireBoolean(map, "has_recurrence", "EventResponse")
        ContractValidators.requireEnum(map, "status", "EventResponse", ContractEnums.EventStatus)
        V2ContractPrimitives.nullableString(map, "category_id", "EventResponse")
        ContractValidators.requireString(map, "timezone", "EventResponse", nonEmpty = true)
        return map
    }

    fun detailResponse(data: Any?) {
        val map = V2ContractPrimitives.objectMap(data, "EventDetailResponse")
        V2ContractPrimitives.requireExactFields(
            map,
            setOf("event", "recurrence", "reminders", "category"),
            "EventDetailResponse",
        )
        val event = validateResponse(map["event"])
        val reminders = map["reminders"] as? List<*>
            ?: throw NativeContractViolation("reminders must be an array.", "data.reminders")
        reminders.forEach(ReminderV2Contracts::response)
        if (map["recurrence"] != null && map["recurrence"] !is Map<*, *>) {
            throw NativeContractViolation("recurrence must be object or null.", "data.recurrence")
        }
        val categoryValue = map["category"]
        if (categoryValue != null) {
            val category = CategoryResponseContracts.active(
                categoryValue,
                "EventDetailResponse.category",
            )
            val categoryId = event["category_id"] as? String
                ?: throw NativeContractViolation(
                    "EventDetailResponse.category requires a non-null event.category_id.",
                    "EventDetailResponse.event.category_id",
                )
            if (category["id"] != categoryId) {
                throw NativeContractViolation(
                    "EventDetailResponse.category.id must equal event.category_id.",
                    "EventDetailResponse.category.id",
                )
            }
        }
    }

    fun listResponse(data: Any?) {
        val map = V2ContractPrimitives.objectMap(data, "EventListResponse")
        V2ContractPrimitives.requireExactFields(map, setOf("items", "pagination"), "EventListResponse")
        val items = map["items"] as? List<*>
            ?: throw NativeContractViolation("items must be an array.", "data.items")
        items.forEach { response(it) }
        V2ContractPrimitives.objectMap(map["pagination"], "PaginationResponse")
    }

    private fun validateOptionalStringArray(
        map: Map<String, Any?>,
        key: String,
        parent: String,
    ) {
        if (!map.containsKey(key)) return
        val values = map[key] as? List<*>
            ?: throw NativeContractViolation("$parent.$key must be an array.", "$parent.$key")
        values.forEachIndexed { index, value ->
            if (value !is String) {
                throw NativeContractViolation(
                    "$parent.$key items must be strings.",
                    "$parent.$key[$index]",
                )
            }
        }
    }

    private fun validateTimeGroup(map: Map<String, Any?>, parent: String) {
        ContractValidators.requireBoolean(map, "is_all_day", parent)
        ContractValidators.requireString(map, "timezone", parent, nonEmpty = true)
        V2ContractPrimitives.validateExclusiveTimePair(
            isAllDay = map["is_all_day"] as Boolean,
            timed = listOf(map["start_at"], map["end_at"]),
            allDay = listOf(map["start_date"], map["end_date"]),
            parent = parent,
        )
    }

    private fun validateRecurrenceAndReminders(map: Map<String, Any?>, parent: String) {
        val recurrence = ContractValidators.optionalObject(map, "recurrence", parent)
        if (recurrence != null) RecurrenceV2Contracts.validate(recurrence, "$parent.recurrence")
        if (map.containsKey("reminders") && map["reminders"] !is List<*>) {
            throw NativeContractViolation("$parent.reminders must be an array.", "$parent.reminders")
        }
        val reminders = if (map.containsKey("reminders")) {
            ContractValidators.optionalObjectArray(map, "reminders", parent)
        } else {
            emptyList()
        }
        if (recurrence != null && map["is_all_day"] == true && reminders.isNotEmpty()) {
            throw NativeContractViolation(
                "All-day recurring Events cannot contain reminders.",
                "$parent.reminders",
            )
        }
        reminders.forEachIndexed { index, reminder ->
            ReminderV2Contracts.validateDraft(reminder, recurrence != null, "$parent.reminders[$index]")
        }
    }
}
