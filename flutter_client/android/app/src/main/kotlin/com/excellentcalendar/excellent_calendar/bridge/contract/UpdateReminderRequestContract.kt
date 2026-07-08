package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec

data class UpdateReminderRequestContract(
    private val payload: Map<String, Any?>,
) {
    fun toJson(): String = NativeContractJsonCodec.encodeObject(payload)

    fun toMap(): Map<String, Any?> = payload

    companion object {
        private val AllowedFields = setOf(
            "id",
            "target_type",
            "target_id",
            "remind_at",
            "advance_minutes",
            "methods",
            "message",
            "source",
        )

        fun fromMethodArguments(arguments: Any?): UpdateReminderRequestContract {
            val map = try {
                NativeContractJsonCodec.normalizeMap(arguments)
            } catch (error: IllegalArgumentException) {
                throw NativeContractViolation(error.message ?: "Invalid MethodChannel arguments.", cause = error)
            }
            validate(map)
            return UpdateReminderRequestContract(map)
        }

        private fun validate(map: Map<String, Any?>) {
            val parent = "UpdateReminderRequest"
            ContractValidators.rejectUnknownFields(map, AllowedFields, parent)
            ContractValidators.requireString(map, "id", parent, nonEmpty = true)
            ContractValidators.optionalEnum(map, "target_type", parent, ContractEnums.ReminderTargetType)
            if (map.containsKey("target_id")) {
                ContractValidators.requireString(map, "target_id", parent, nonEmpty = true)
            }
            ContractValidators.optionalString(map, "remind_at", parent)
            ContractValidators.optionalInteger(map, "advance_minutes", parent)
            when (val advanceMinutes = map["advance_minutes"]) {
                is Int -> if (advanceMinutes < 0) {
                    throw NativeContractViolation("$parent.advance_minutes must be >= 0.", "$parent.advance_minutes")
                }
                is Long -> if (advanceMinutes < 0L) {
                    throw NativeContractViolation("$parent.advance_minutes must be >= 0.", "$parent.advance_minutes")
                }
            }
            ContractValidators.optionalStringArray(map, "methods", parent, ContractEnums.ReminderMethods)
            val methods = map["methods"]
            if (methods != null) {
                if (methods !is List<*> || methods.isEmpty()) {
                    throw NativeContractViolation("$parent.methods must be a non-empty array.", "$parent.methods")
                }
                if (methods.toSet().size != methods.size) {
                    throw NativeContractViolation("$parent.methods must not contain duplicates.", "$parent.methods")
                }
            }
            ContractValidators.optionalString(map, "message", parent)
            ContractValidators.optionalEnum(map, "source", parent, ContractEnums.ReminderSource)
        }
    }
}
