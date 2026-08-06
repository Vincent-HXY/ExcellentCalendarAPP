package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec

/**
 * reminder.create 的请求合约。
 *
 * Kotlin 只校验跨层边界形状：字段是否存在、类型是否明显错误、枚举是否来自 contracts/enums.yaml。
 * remind_at 是否合理、target 是否存在等领域裁决仍然交给 C++。
 */
data class CreateReminderRequestContract(
    private val payload: Map<String, Any?>,
) {
    fun toJson(): String = NativeContractJsonCodec.encodeObject(payload)

    fun toMap(): Map<String, Any?> = payload

    companion object {
        private val AllowedFields = setOf(
            "target_type",
            "target_id",
            "remind_at",
            "advance_minutes",
            "methods",
            "message",
            "is_enabled",
            "source",
        )

        fun fromMethodArguments(arguments: Any?): CreateReminderRequestContract {
            val map = try {
                NativeContractJsonCodec.normalizeMap(arguments)
            } catch (error: IllegalArgumentException) {
                throw NativeContractViolation(error.message ?: "Invalid MethodChannel arguments.", cause = error)
            }
            validate(map)
            return CreateReminderRequestContract(map)
        }

        private fun validate(map: Map<String, Any?>) {
            val parent = "CreateReminderRequest"
            ContractValidators.rejectUnknownFields(map, AllowedFields, parent)
            ContractValidators.requireEnum(map, "target_type", parent, setOf("event", "habit", "anniversary"))
            ContractValidators.requireString(map, "target_id", parent, nonEmpty = true)
            ContractValidators.optionalString(map, "remind_at", parent)
            ContractValidators.optionalInteger(map, "advance_minutes", parent)
            val remindAt = map["remind_at"]
            val advanceMinutes = map["advance_minutes"]
            if (remindAt == null && advanceMinutes == null) {
                throw NativeContractViolation(
                    "$parent requires remind_at or advance_minutes.",
                    "$parent.remind_at",
                )
            }
            when (advanceMinutes) {
                is Int -> if (advanceMinutes < 0) {
                    throw NativeContractViolation("$parent.advance_minutes must be >= 0.", "$parent.advance_minutes")
                }
                is Long -> if (advanceMinutes < 0L) {
                    throw NativeContractViolation("$parent.advance_minutes must be >= 0.", "$parent.advance_minutes")
                }
            }
            ContractValidators.optionalStringArray(map, "methods", parent, ContractEnums.ReminderMethods)
            val methods = map["methods"]
            if (methods !is List<*> || methods.isEmpty()) {
                throw NativeContractViolation("$parent.methods must be a non-empty array.", "$parent.methods")
            }
            if (methods.toSet().size != methods.size) {
                throw NativeContractViolation("$parent.methods must not contain duplicates.", "$parent.methods")
            }
            ContractValidators.optionalString(map, "message", parent)
            ContractValidators.requireBoolean(map, "is_enabled", parent)
            ContractValidators.requireEnum(map, "source", parent, ContractEnums.ReminderSource)
        }
    }
}
