package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec

data class ReopenEventRequestContract(
    private val payload: Map<String, Any?>,
) {
    fun toJson(): String = NativeContractJsonCodec.encodeObject(payload)

    fun toMap(): Map<String, Any?> = payload

    companion object {
        private val AllowedFields = setOf(
            "event_id",
            "occurrence_start_at",
        )

        fun fromMethodArguments(arguments: Any?): ReopenEventRequestContract {
            val map = try {
                NativeContractJsonCodec.normalizeMap(arguments)
            } catch (error: IllegalArgumentException) {
                throw NativeContractViolation(error.message ?: "Invalid MethodChannel arguments.", cause = error)
            }
            validate(map)
            return ReopenEventRequestContract(map)
        }

        private fun validate(map: Map<String, Any?>) {
            val parent = "ReopenEventRequest"
            ContractValidators.rejectUnknownFields(map, AllowedFields, parent)
            ContractValidators.requireString(map, "event_id", parent, nonEmpty = true)
            ContractValidators.optionalString(map, "occurrence_start_at", parent)
        }
    }
}
