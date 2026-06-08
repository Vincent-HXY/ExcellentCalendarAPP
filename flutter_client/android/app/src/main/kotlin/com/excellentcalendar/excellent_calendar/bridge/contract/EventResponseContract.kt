package com.excellentcalendar.excellent_calendar.bridge.contract

object EventResponseContract {
    private val AllowedFields = setOf(
        "id",
        "title",
        "content",
        "start_at",
        "end_at",
        "is_all_day",
        "has_recurrence",
        "status",
        "completed_at",
        "recurrence_id",
        "category_id",
        "importance",
        "location",
        "timezone",
        "source",
        "created_at",
        "updated_at",
        "deleted_at",
    )

    fun validate(data: Any?) {
        if (data !is Map<*, *>) {
            throw NativeContractViolation("EventResponse data must be an object.", "data")
        }
        @Suppress("UNCHECKED_CAST")
        validateMap(data as Map<String, Any?>, "EventResponse")
    }

    fun validateMap(map: Map<String, Any?>, parent: String) {
        ContractValidators.rejectUnknownFields(map, AllowedFields, parent)
        ContractValidators.requireString(map, "id", parent, nonEmpty = true)
        ContractValidators.requireString(map, "title", parent, nonEmpty = true)
        ContractValidators.optionalString(map, "content", parent)
        ContractValidators.requireString(map, "start_at", parent, nonEmpty = true)
        ContractValidators.requireString(map, "end_at", parent, nonEmpty = true)
        ContractValidators.requireBoolean(map, "is_all_day", parent)
        ContractValidators.requireBoolean(map, "has_recurrence", parent)
        ContractValidators.requireEnum(map, "status", parent, ContractEnums.EventStatus)
        ContractValidators.optionalString(map, "completed_at", parent)
        ContractValidators.optionalString(map, "recurrence_id", parent)
        ContractValidators.optionalString(map, "category_id", parent)
        ContractValidators.optionalEnum(map, "importance", parent, ContractEnums.Importance)
        ContractValidators.optionalString(map, "location", parent)
        ContractValidators.optionalString(map, "timezone", parent)
        ContractValidators.requireEnum(map, "source", parent, ContractEnums.CreateEventSource)
        ContractValidators.requireString(map, "created_at", parent, nonEmpty = true)
        ContractValidators.requireString(map, "updated_at", parent, nonEmpty = true)
        ContractValidators.optionalString(map, "deleted_at", parent)
    }
}
