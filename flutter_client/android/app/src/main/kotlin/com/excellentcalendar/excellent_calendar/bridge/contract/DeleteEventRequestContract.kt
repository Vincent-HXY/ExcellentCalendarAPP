package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec

data class DeleteEventRequestContract(
    private val payload: Map<String, Any?>,
) {
    fun toJson(): String = NativeContractJsonCodec.encodeObject(payload)

    fun toMap(): Map<String, Any?> = payload

    companion object {
        private val AllowedFields = setOf(
            "id",
            "delete_mode",
            "recurrence_delete_scope",
            "occurrence_start_at",
            "reason",
        )

        fun fromMethodArguments(arguments: Any?): DeleteEventRequestContract {
            val map = try {
                NativeContractJsonCodec.normalizeMap(arguments)
            } catch (error: IllegalArgumentException) {
                throw NativeContractViolation(error.message ?: "Invalid MethodChannel arguments.", cause = error)
            }
            validate(map)
            return DeleteEventRequestContract(map)
        }

        private fun validate(map: Map<String, Any?>) {
            val parent = "DeleteEventRequest"
            ContractValidators.rejectUnknownFields(map, AllowedFields, parent)
            ContractValidators.requireString(map, "id", parent, nonEmpty = true)
            ContractValidators.requireEnum(map, "delete_mode", parent, ContractEnums.DeleteMode)
            ContractValidators.optionalEnum(
                map,
                "recurrence_delete_scope",
                parent,
                ContractEnums.RecurrenceDeleteScope,
            )
            ContractValidators.optionalString(map, "occurrence_start_at", parent)
            ContractValidators.optionalString(map, "reason", parent)
        }
    }
}
