package com.excellentcalendar.excellent_calendar.bridge.contract

/** Contract v2 validation owned by the recurrence module. */
internal object RecurrenceV2Contracts {
    fun validate(map: Map<String, Any?>, parent: String) {
        ContractValidators.rejectUnknownFields(map, setOf("frequency", "interval", "end_at", "count"), parent)
        V2ContractPrimitives.requireFields(map, setOf("frequency", "interval", "end_at", "count"), parent)
        ContractValidators.requireEnum(map, "frequency", parent, ContractEnums.RecurrenceFrequency)
        V2ContractPrimitives.positiveInteger(map, "interval", parent)
        if (V2ContractPrimitives.integerValue(map["interval"]) != 1L) {
            throw NativeContractViolation("$parent.interval must equal 1.", "$parent.interval")
        }
        if (map["end_at"] != null || map["count"] != null) {
            throw NativeContractViolation("$parent must be infinite in Contract v2.", parent)
        }
    }
}
