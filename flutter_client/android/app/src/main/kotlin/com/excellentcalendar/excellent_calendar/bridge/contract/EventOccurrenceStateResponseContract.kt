package com.excellentcalendar.excellent_calendar.bridge.contract

object EventOccurrenceStateResponseContract {
    private val AllowedFields = setOf(
        "id",
        "event_id",
        "occurrence_start_at",
        "status",
        "completed_at",
        "note",
        "source",
        "created_at",
        "updated_at",
        "deleted_at",
    )

    fun validate(data: Any?) {
        if (data !is Map<*, *>) {
            throw NativeContractViolation("EventOccurrenceStateResponse data must be an object.", "data")
        }
        @Suppress("UNCHECKED_CAST")
        validateMap(data as Map<String, Any?>, "EventOccurrenceStateResponse")
    }

    fun validateMap(map: Map<String, Any?>, parent: String) {
        ContractValidators.rejectUnknownFields(map, AllowedFields, parent)
        ContractValidators.requireString(map, "id", parent, nonEmpty = true)
        ContractValidators.requireString(map, "event_id", parent, nonEmpty = true)
        ContractValidators.requireString(map, "occurrence_start_at", parent, nonEmpty = true)
        ContractValidators.requireEnum(map, "status", parent, ContractEnums.EventOccurrenceStatus)
        ContractValidators.optionalString(map, "completed_at", parent)
        ContractValidators.optionalString(map, "note", parent)
        ContractValidators.requireEnum(map, "source", parent, ContractEnums.ReminderSource)
        ContractValidators.requireString(map, "created_at", parent, nonEmpty = true)
        ContractValidators.requireString(map, "updated_at", parent, nonEmpty = true)
        ContractValidators.optionalString(map, "deleted_at", parent)
    }
}
