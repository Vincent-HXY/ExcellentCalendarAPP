package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec

data class CompleteEventRequestContract(
    private val payload: Map<String, Any?>,
) {
    fun toJson(): String = NativeContractJsonCodec.encodeObject(payload)

    fun toMap(): Map<String, Any?> = payload

    companion object {
        private val AllowedFields = setOf(
            "event_id",
            "occurrence_start_at",
            "completed_at",
            "source",
            "note",
        )

        fun fromMethodArguments(arguments: Any?): CompleteEventRequestContract {
            val map = try {
                NativeContractJsonCodec.normalizeMap(arguments)
            } catch (error: IllegalArgumentException) {
                throw NativeContractViolation(error.message ?: "Invalid MethodChannel arguments.", cause = error)
            }
            validate(map)
            return CompleteEventRequestContract(map)
        }

        private fun validate(map: Map<String, Any?>) {
            val parent = "CompleteEventRequest"
            ContractValidators.rejectUnknownFields(map, AllowedFields, parent)
            ContractValidators.requireString(map, "event_id", parent, nonEmpty = true)
            ContractValidators.optionalString(map, "occurrence_start_at", parent)
            ContractValidators.requireString(map, "completed_at", parent, nonEmpty = true)
            ContractValidators.requireEnum(map, "source", parent, ContractEnums.ReminderSource)
            ContractValidators.optionalString(map, "note", parent)
        }
    }
}
