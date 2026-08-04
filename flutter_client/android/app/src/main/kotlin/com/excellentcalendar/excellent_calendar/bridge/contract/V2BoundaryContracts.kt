package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec

class V2JsonRequest internal constructor(val value: Map<String, Any?>) {
    fun toJson(): String = NativeContractJsonCodec.encodeObject(value)
}

object V2RequestContracts {
    private val createEventFields = setOf(
        "title", "content", "start_at", "end_at", "start_date", "end_date", "is_all_day",
        "category_id", "importance", "location", "timezone", "source", "recurrence", "reminders",
    )
    private val updateEventFields = createEventFields + setOf("id", "expected_recurrence_revision")
    private val occurrenceIdentityFields = setOf(
        "event_id", "recurrence_revision", "occurrence_key", "occurrence_start_at", "occurrence_start_date",
    )

    fun createEvent(arguments: Any?): V2JsonRequest = request(arguments, "CreateEventRequest") { map ->
        ContractValidators.rejectUnknownFields(map, createEventFields, "CreateEventRequest")
        requireFields(map, setOf("title", "start_at", "end_at", "start_date", "end_date", "is_all_day", "timezone", "source"), "CreateEventRequest")
        ContractValidators.requireString(map, "title", "CreateEventRequest", nonEmpty = true)
        validateEventTimeGroup(map, "CreateEventRequest")
        validateRecurrenceAndReminders(map, "CreateEventRequest")
    }

    fun updateEvent(arguments: Any?): V2JsonRequest = request(arguments, "UpdateEventRequest") { map ->
        ContractValidators.rejectUnknownFields(map, updateEventFields, "UpdateEventRequest")
        ContractValidators.requireString(map, "id", "UpdateEventRequest", nonEmpty = true)
        val timeFields = setOf("start_at", "end_at", "start_date", "end_date", "is_all_day", "timezone")
        if (map.keys.any { it in timeFields }) {
            requireFields(map, timeFields, "UpdateEventRequest")
            validateEventTimeGroup(map, "UpdateEventRequest")
        }
        if (map.containsKey("recurrence") && map["recurrence"] == null) {
            throw NativeContractViolation("UpdateEventRequest.recurrence cannot be null.", "UpdateEventRequest.recurrence")
        }
        validateRecurrenceAndReminders(map, "UpdateEventRequest")
    }

    fun deleteEvent(arguments: Any?): V2JsonRequest = request(arguments, "DeleteEventRequest") { map ->
        ContractValidators.rejectUnknownFields(map, setOf("id", "delete_mode", "recurrence_delete_scope", "expected_recurrence_revision", "reason"), "DeleteEventRequest")
        requireFields(map, setOf("id", "delete_mode", "recurrence_delete_scope", "expected_recurrence_revision"), "DeleteEventRequest")
        ContractValidators.requireString(map, "id", "DeleteEventRequest", nonEmpty = true)
        ContractValidators.requireEnum(map, "delete_mode", "DeleteEventRequest", setOf("soft", "hard"))
        val scope = map["recurrence_delete_scope"]
        if (scope != null && scope != "all_occurrences") {
            throw NativeContractViolation("Only all_occurrences is supported for recurring Event deletion.", "DeleteEventRequest.recurrence_delete_scope")
        }
        nullableInteger(map, "expected_recurrence_revision", "DeleteEventRequest")
        ContractValidators.optionalString(map, "reason", "DeleteEventRequest")
    }

    fun eventId(arguments: Any?, parent: String = "GetEventDetailRequest"): V2JsonRequest = request(arguments, parent) { map ->
        ContractValidators.rejectUnknownFields(map, setOf("id"), parent)
        ContractValidators.requireString(map, "id", parent, nonEmpty = true)
    }

    fun listOccurrences(arguments: Any?): V2JsonRequest = request(arguments, "ListEventOccurrencesRequest") { map ->
        val allowed = setOf("event_id", "recurrence_revision", "is_all_day", "range_start_at", "range_end_at", "range_start_date", "range_end_date", "cursor", "limit")
        ContractValidators.rejectUnknownFields(map, allowed, "ListEventOccurrencesRequest")
        requireFields(map, allowed, "ListEventOccurrencesRequest")
        ContractValidators.requireString(map, "event_id", "ListEventOccurrencesRequest", nonEmpty = true)
        positiveInteger(map, "recurrence_revision", "ListEventOccurrencesRequest")
        ContractValidators.requireBoolean(map, "is_all_day", "ListEventOccurrencesRequest")
        nullableString(map, "cursor", "ListEventOccurrencesRequest")
        positiveInteger(map, "limit", "ListEventOccurrencesRequest", maximum = 200)
        validateExclusiveTimePair(
            isAllDay = map["is_all_day"] as Boolean,
            timed = listOf(map["range_start_at"], map["range_end_at"]),
            allDay = listOf(map["range_start_date"], map["range_end_date"]),
            parent = "ListEventOccurrencesRequest",
        )
    }

    fun occurrenceOperation(arguments: Any?): V2JsonRequest = request(arguments, "EventOccurrenceOperationRequest") { map ->
        ContractValidators.rejectUnknownFields(map, occurrenceIdentityFields, "EventOccurrenceOperationRequest")
        requireFields(map, occurrenceIdentityFields, "EventOccurrenceOperationRequest")
        ContractValidators.requireString(map, "event_id", "EventOccurrenceOperationRequest", nonEmpty = true)
        positiveInteger(map, "recurrence_revision", "EventOccurrenceOperationRequest")
        ContractValidators.requireString(map, "occurrence_key", "EventOccurrenceOperationRequest", nonEmpty = true)
        validateExactlyOneString(map["occurrence_start_at"], map["occurrence_start_date"], "EventOccurrenceOperationRequest")
    }

    fun seriesOperation(arguments: Any?): V2JsonRequest = request(arguments, "EventSeriesOperationRequest") { map ->
        ContractValidators.rejectUnknownFields(map, setOf("event_id", "recurrence_revision"), "EventSeriesOperationRequest")
        ContractValidators.requireString(map, "event_id", "EventSeriesOperationRequest", nonEmpty = true)
        positiveInteger(map, "recurrence_revision", "EventSeriesOperationRequest")
    }

    fun searchEvent(arguments: Any?): V2JsonRequest = request(arguments, "SearchEventRequest") { map ->
        val allowed = setOf(
            "keyword", "start_at_from", "start_at_to", "start_date_from", "start_date_to", "status",
            "category_ids", "importance", "location", "has_recurrence", "source", "include_deleted",
            "pagination", "sort_by", "sort_direction",
        )
        ContractValidators.rejectUnknownFields(map, allowed, "SearchEventRequest")
        ContractValidators.optionalStringArray(map, "status", "SearchEventRequest", ContractEnums.EventStatus)
        ContractValidators.optionalStringArray(map, "importance", "SearchEventRequest", ContractEnums.Importance)
        ContractValidators.optionalStringArray(map, "source", "SearchEventRequest", ContractEnums.CreateEventSource)
        ContractValidators.optionalEnum(map, "sort_direction", "SearchEventRequest", ContractEnums.SortDirection)
    }

    fun completeEvent(arguments: Any?): V2JsonRequest = request(arguments, "CompleteEventRequest") { map ->
        ContractValidators.rejectUnknownFields(map, setOf("event_id", "source", "note"), "CompleteEventRequest")
        ContractValidators.requireString(map, "event_id", "CompleteEventRequest", nonEmpty = true)
        ContractValidators.requireEnum(map, "source", "CompleteEventRequest", ContractEnums.CompleteEventSource)
        ContractValidators.optionalString(map, "note", "CompleteEventRequest")
    }

    fun reopenEvent(arguments: Any?): V2JsonRequest = request(arguments, "ReopenEventRequest") { map ->
        ContractValidators.rejectUnknownFields(map, setOf("event_id"), "ReopenEventRequest")
        ContractValidators.requireString(map, "event_id", "ReopenEventRequest", nonEmpty = true)
    }

    fun createReminder(arguments: Any?): V2JsonRequest = request(arguments, "CreateReminderRequest") { map ->
        val allowed = setOf("target_type", "target_id", "remind_at", "advance_minutes", "methods", "message", "is_enabled", "source")
        ContractValidators.rejectUnknownFields(map, allowed, "CreateReminderRequest")
        requireFields(map, setOf("target_type", "target_id", "methods", "is_enabled", "source"), "CreateReminderRequest")
        validateOrdinaryReminder(map, "CreateReminderRequest", requireTime = true)
    }

    fun updateReminder(arguments: Any?): V2JsonRequest = request(arguments, "UpdateReminderRequest") { map ->
        val allowed = setOf("reminder_id", "target_type", "target_id", "remind_at", "advance_minutes", "methods", "message", "source")
        ContractValidators.rejectUnknownFields(map, allowed, "UpdateReminderRequest")
        ContractValidators.requireString(map, "reminder_id", "UpdateReminderRequest", nonEmpty = true)
        if (map.containsKey("methods")) validateMethods(map, "UpdateReminderRequest")
        if (map.containsKey("remind_at") && map["remind_at"] != null && map["remind_at"] !is String) throw NativeContractViolation("Invalid remind_at.", "UpdateReminderRequest.remind_at")
        nullableInteger(map, "advance_minutes", "UpdateReminderRequest")
    }

    fun cancelReminder(arguments: Any?): V2JsonRequest = request(arguments, "CancelReminderRequest") { map ->
        ContractValidators.rejectUnknownFields(map, setOf("reminder_id"), "CancelReminderRequest")
        ContractValidators.requireString(map, "reminder_id", "CancelReminderRequest", nonEmpty = true)
    }

    fun listReminders(arguments: Any?): V2JsonRequest = request(arguments, "ListRemindersRequest") { map ->
        val allowed = setOf(
            "target_type", "target_id", "recurrence_revision", "occurrence_key", "remind_at_from", "remind_at_to",
            "methods", "status", "is_enabled", "include_deleted", "pagination", "sort_by", "sort_direction",
        )
        ContractValidators.rejectUnknownFields(map, allowed, "ListRemindersRequest")
        ContractValidators.optionalStringArray(map, "methods", "ListRemindersRequest", ContractEnums.ReminderMethods)
        ContractValidators.optionalStringArray(map, "status", "ListRemindersRequest", ContractEnums.ReminderStatus)
        ContractValidators.optionalEnum(map, "sort_direction", "ListRemindersRequest", ContractEnums.SortDirection)
    }

    fun passthrough(arguments: Any?, parent: String): V2JsonRequest = request(arguments, parent) { }

    private fun request(arguments: Any?, parent: String, validator: (Map<String, Any?>) -> Unit): V2JsonRequest {
        val map = try {
            NativeContractJsonCodec.normalizeMap(arguments)
        } catch (error: IllegalArgumentException) {
            throw NativeContractViolation("$parent must be an object.", parent, error)
        }
        validator(map)
        return V2JsonRequest(map)
    }

    private fun validateEventTimeGroup(map: Map<String, Any?>, parent: String) {
        ContractValidators.requireBoolean(map, "is_all_day", parent)
        ContractValidators.requireString(map, "timezone", parent, nonEmpty = true)
        validateExclusiveTimePair(
            isAllDay = map["is_all_day"] as Boolean,
            timed = listOf(map["start_at"], map["end_at"]),
            allDay = listOf(map["start_date"], map["end_date"]),
            parent = parent,
        )
    }

    private fun validateExclusiveTimePair(isAllDay: Boolean, timed: List<Any?>, allDay: List<Any?>, parent: String) {
        val valid = if (isAllDay) allDay.all { it is String && it.isNotBlank() } && timed.all { it == null }
        else timed.all { it is String && it.isNotBlank() } && allDay.all { it == null }
        if (!valid) throw NativeContractViolation("$parent timed/all-day fields are mutually exclusive.", "$parent.is_all_day")
    }

    private fun validateExactlyOneString(first: Any?, second: Any?, parent: String) {
        val valid = (first is String && first.isNotBlank() && second == null) ||
            (second is String && second.isNotBlank() && first == null)
        if (!valid) throw NativeContractViolation("$parent must carry exactly one planned occurrence start.", "$parent.occurrence_start_at")
    }

    private fun validateRecurrenceAndReminders(map: Map<String, Any?>, parent: String) {
        val recurrence = ContractValidators.optionalObject(map, "recurrence", parent)
        if (recurrence != null) validateRecurrence(recurrence, "$parent.recurrence")
        if (map.containsKey("reminders") && map["reminders"] !is List<*>) {
            throw NativeContractViolation("$parent.reminders must be an array.", "$parent.reminders")
        }
        val reminders = if (map.containsKey("reminders")) ContractValidators.optionalObjectArray(map, "reminders", parent) else emptyList()
        if (recurrence != null && map["is_all_day"] == true && reminders.isNotEmpty()) {
            throw NativeContractViolation("All-day recurring Events cannot contain reminders.", "$parent.reminders")
        }
        reminders.forEachIndexed { index, reminder -> validateReminderDraft(reminder, recurrence != null, "$parent.reminders[$index]") }
    }

    private fun validateRecurrence(map: Map<String, Any?>, parent: String) {
        ContractValidators.rejectUnknownFields(map, setOf("frequency", "interval", "end_at", "count"), parent)
        requireFields(map, setOf("frequency", "interval", "end_at", "count"), parent)
        ContractValidators.requireEnum(map, "frequency", parent, ContractEnums.RecurrenceFrequency)
        positiveInteger(map, "interval", parent)
        if (integerValue(map["interval"]) != 1L) throw NativeContractViolation("$parent.interval must equal 1.", "$parent.interval")
        if (map["end_at"] != null || map["count"] != null) throw NativeContractViolation("$parent must be infinite in Contract v2.", parent)
    }

    private fun validateReminderDraft(map: Map<String, Any?>, recurring: Boolean, parent: String) {
        val allowed = if (recurring) setOf("target_type", "target_id", "advance_minutes", "methods", "message", "is_enabled", "source")
        else setOf("target_type", "target_id", "remind_at", "advance_minutes", "methods", "message", "is_enabled", "source")
        ContractValidators.rejectUnknownFields(map, allowed, parent)
        if (recurring) {
            requireFields(map, setOf("target_type", "advance_minutes", "methods", "message", "is_enabled", "source"), parent)
            val methods = map["methods"]
            if (map["target_type"] != "event" || methods != listOf("popup") || map["is_enabled"] != true) {
                throw NativeContractViolation("Recurring reminder templates support enabled popup Event reminders only.", parent)
            }
            positiveInteger(map, "advance_minutes", parent, minimum = 0)
            nullableNonBlankString(map, "target_id", parent)
            nullableString(map, "message", parent)
            ContractValidators.requireEnum(map, "source", parent, ContractEnums.ReminderSource)
        } else {
            requireFields(map, setOf("target_type", "methods", "is_enabled", "source"), parent)
            ContractValidators.requireEnum(map, "target_type", parent, setOf("event", "anniversary"))
            nullableNonBlankString(map, "target_id", parent)
            nullableString(map, "message", parent)
            ContractValidators.requireBoolean(map, "is_enabled", parent)
            if (map["is_enabled"] != true) throw NativeContractViolation("$parent.is_enabled must be true.", "$parent.is_enabled")
            ContractValidators.requireEnum(map, "source", parent, ContractEnums.ReminderSource)
            validateMethods(map, parent)
            validateExactlyOneReminderTime(map, parent)
        }
    }

    private fun validateOrdinaryReminder(map: Map<String, Any?>, parent: String, requireTime: Boolean) {
        ContractValidators.requireEnum(map, "target_type", parent, ContractEnums.ReminderTargetType)
        ContractValidators.requireString(map, "target_id", parent, nonEmpty = true)
        ContractValidators.requireBoolean(map, "is_enabled", parent)
        if (map["is_enabled"] != true) throw NativeContractViolation("$parent.is_enabled must be true.", "$parent.is_enabled")
        ContractValidators.requireEnum(map, "source", parent, ContractEnums.ReminderSource)
        validateMethods(map, parent)
        if (requireTime) validateExactlyOneReminderTime(map, parent)
    }

    private fun validateMethods(map: Map<String, Any?>, parent: String) {
        val methods = map["methods"]
        if (methods !is List<*> || methods.isEmpty() || methods.any { it !is String || it !in ContractEnums.ReminderMethods } || methods.distinct().size != methods.size) {
            throw NativeContractViolation("$parent.methods is invalid.", "$parent.methods")
        }
    }

    private fun validateExactlyOneReminderTime(map: Map<String, Any?>, parent: String) {
        val remindAt = map["remind_at"]
        val advance = map["advance_minutes"]
        val valid = (
            map.containsKey("remind_at") && remindAt is String && remindAt.isNotBlank() && advance == null
            ) || (
            map.containsKey("advance_minutes") && remindAt == null && integerValue(advance)?.let { it >= 0 } == true
            )
        if (!valid) throw NativeContractViolation("$parent must contain exactly one reminder time form.", "$parent.remind_at")
    }

    private fun requireFields(map: Map<String, Any?>, fields: Set<String>, parent: String) {
        fields.firstOrNull { !map.containsKey(it) }?.let { throw NativeContractViolation("$parent.$it is required.", "$parent.$it") }
    }

    private fun nullableString(map: Map<String, Any?>, key: String, parent: String) {
        if (map[key] != null && map[key] !is String) throw NativeContractViolation("$parent.$key must be string or null.", "$parent.$key")
    }

    private fun nullableNonBlankString(map: Map<String, Any?>, key: String, parent: String) {
        val value = map[key]
        if (value != null && (value !is String || value.isBlank())) {
            throw NativeContractViolation("$parent.$key must be a non-empty string or null.", "$parent.$key")
        }
    }

    private fun nullableInteger(map: Map<String, Any?>, key: String, parent: String) {
        val value = map[key]
        if (value != null && value !is Int && value !is Long) throw NativeContractViolation("$parent.$key must be integer or null.", "$parent.$key")
    }

    private fun positiveInteger(map: Map<String, Any?>, key: String, parent: String, minimum: Int = 1, maximum: Int? = null) {
        val value = integerValue(map[key])
            ?: throw NativeContractViolation("$parent.$key must be integer.", "$parent.$key")
        if (value < minimum || (maximum != null && value > maximum)) throw NativeContractViolation("$parent.$key is out of range.", "$parent.$key")
    }

    private fun integerValue(value: Any?): Long? = when (value) {
        is Byte -> value.toLong()
        is Short -> value.toLong()
        is Int -> value.toLong()
        is Long -> value
        else -> null
    }
}

object V2ResponseContracts {
    private val eventFields = setOf(
        "id", "title", "content", "start_at", "end_at", "start_date", "end_date", "is_all_day",
        "has_recurrence", "status", "completed_at", "recurrence_id", "recurrence_revision", "category_id",
        "importance", "location", "timezone", "source", "created_at", "updated_at", "deleted_at",
    )
    private val reminderFields = setOf(
        "reminder_id", "target_type", "target_id", "recurrence_revision", "occurrence_key", "occurrence_start_at",
        "remind_at", "advance_minutes", "methods", "message", "is_enabled", "status", "scheduled_at",
        "last_triggered_at", "failure_reason", "last_cancellation_reason", "last_cancelled_at", "expiration_reason",
        "expired_at", "reactivated_at", "reactivation_count", "created_at", "updated_at", "deleted_at",
    )

    fun event(data: Any?) {
        val map = objectMap(data, "EventResponse")
        requireExactFields(map, eventFields, "EventResponse")
        ContractValidators.requireBoolean(map, "is_all_day", "EventResponse")
        ContractValidators.requireBoolean(map, "has_recurrence", "EventResponse")
        ContractValidators.requireEnum(map, "status", "EventResponse", ContractEnums.EventStatus)
        ContractValidators.requireString(map, "timezone", "EventResponse", nonEmpty = true)
    }

    fun eventDetail(data: Any?) {
        val map = objectMap(data, "EventDetailResponse")
        requireExactFields(map, setOf("event", "recurrence", "reminders", "category"), "EventDetailResponse")
        event(map["event"])
        val reminders = map["reminders"] as? List<*> ?: throw NativeContractViolation("reminders must be an array.", "data.reminders")
        reminders.forEach(::reminder)
        if (map["recurrence"] != null && map["recurrence"] !is Map<*, *>) throw NativeContractViolation("recurrence must be object or null.", "data.recurrence")
    }

    fun eventList(data: Any?) {
        val map = objectMap(data, "EventListResponse")
        requireExactFields(map, setOf("items", "pagination"), "EventListResponse")
        val items = map["items"] as? List<*> ?: throw NativeContractViolation("items must be an array.", "data.items")
        items.forEach(::event)
        objectMap(map["pagination"], "PaginationResponse")
    }

    fun occurrence(data: Any?) {
        val map = objectMap(data, "EventOccurrenceResponse")
        requireExactFields(
            map,
            setOf("event_id", "recurrence_revision", "occurrence_key", "occurrence_start_at", "occurrence_end_at", "occurrence_start_date", "occurrence_end_date", "timezone", "state"),
            "EventOccurrenceResponse",
        )
        ContractValidators.requireString(map, "event_id", "EventOccurrenceResponse", nonEmpty = true)
        ContractValidators.requireString(map, "occurrence_key", "EventOccurrenceResponse", nonEmpty = true)
        if (map["state"] != null) occurrenceState(map["state"])
    }

    fun occurrenceState(data: Any?) {
        val map = objectMap(data, "EventOccurrenceStateResponse")
        requireExactFields(
            map,
            setOf("event_id", "recurrence_revision", "occurrence_key", "occurrence_start_at", "occurrence_start_date", "status", "state_changed_at", "reopened_at", "created_at", "updated_at"),
            "EventOccurrenceStateResponse",
        )
        ContractValidators.requireEnum(map, "status", "EventOccurrenceStateResponse", setOf("scheduled", "completed", "skipped", "cancelled"))
    }

    fun occurrenceList(data: Any?) {
        val map = objectMap(data, "EventOccurrenceListResponse")
        requireExactFields(map, setOf("items", "has_more", "next_cursor"), "EventOccurrenceListResponse")
        val items = map["items"] as? List<*> ?: throw NativeContractViolation("items must be an array.", "data.items")
        if (items.size > 200) throw NativeContractViolation("items exceeds 200.", "data.items")
        items.forEach(::occurrence)
    }

    fun reminder(data: Any?) {
        val map = objectMap(data, "ReminderResponse")
        requireExactFields(map, reminderFields, "ReminderResponse")
        ContractValidators.requireEnum(map, "status", "ReminderResponse", setOf("pending", "scheduled", "sent", "failed", "cancelled", "expired"))
        ContractValidators.requireString(map, "reminder_id", "ReminderResponse", nonEmpty = true)
        ContractValidators.requireString(map, "remind_at", "ReminderResponse", nonEmpty = true)
    }

    fun reminderList(data: Any?) {
        val map = objectMap(data, "ReminderListResponse")
        requireExactFields(map, setOf("items", "pagination"), "ReminderListResponse")
        val items = map["items"] as? List<*> ?: throw NativeContractViolation("items must be an array.", "data.items")
        items.forEach(::reminder)
        objectMap(map["pagination"], "PaginationResponse")
    }

    @Suppress("UNCHECKED_CAST")
    private fun objectMap(data: Any?, parent: String): Map<String, Any?> =
        data as? Map<String, Any?> ?: throw NativeContractViolation("$parent must be an object.", "data")

    private fun requireExactFields(map: Map<String, Any?>, fields: Set<String>, parent: String) {
        ContractValidators.rejectUnknownFields(map, fields, parent)
        fields.firstOrNull { !map.containsKey(it) }?.let { throw NativeContractViolation("$parent.$it is required.", "$parent.$it") }
    }
}
