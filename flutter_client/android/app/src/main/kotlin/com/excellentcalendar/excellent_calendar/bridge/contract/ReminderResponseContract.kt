package com.excellentcalendar.excellent_calendar.bridge.contract

/** ReminderResponse 合约校验与调度所需字段读取。 */
data class ReminderContract(
    val id: String,
    val remindAt: String,
    val methods: List<String>,
    val isEnabled: Boolean,
    val status: String,
) {
    companion object {
        fun fromData(data: Any?): ReminderContract {
            if (data !is Map<*, *>) {
                throw NativeContractViolation("ReminderResponse data must be an object.", "data")
            }
            @Suppress("UNCHECKED_CAST")
            val map = data as Map<String, Any?>
            ReminderResponseContract.validateMap(map, "ReminderResponse")
            @Suppress("UNCHECKED_CAST")
            return ReminderContract(
                id = map["id"] as String,
                remindAt = map["remind_at"] as String,
                methods = (map["methods"] as List<*>).map { it as String },
                isEnabled = map["is_enabled"] as Boolean,
                status = map["status"] as String,
            )
        }
    }
}

object ReminderResponseContract {
    private val AllowedFields = setOf(
        "id",
        "target_type",
        "target_id",
        "remind_at",
        "methods",
        "advance_minutes",
        "message",
        "is_enabled",
        "status",
        "scheduled_at",
        "last_triggered_at",
        "failure_reason",
        "created_at",
        "updated_at",
        "deleted_at",
    )

    fun validate(data: Any?) {
        if (data !is Map<*, *>) {
            throw NativeContractViolation("ReminderResponse data must be an object.", "data")
        }
        @Suppress("UNCHECKED_CAST")
        validateMap(data as Map<String, Any?>, "ReminderResponse")
    }

    fun validateMap(map: Map<String, Any?>, parent: String) {
        ContractValidators.rejectUnknownFields(map, AllowedFields, parent)
        ContractValidators.requireString(map, "id", parent, nonEmpty = true)
        ContractValidators.requireEnum(map, "target_type", parent, setOf("event", "habit", "anniversary"))
        ContractValidators.requireString(map, "target_id", parent, nonEmpty = true)
        ContractValidators.requireString(map, "remind_at", parent, nonEmpty = true)
        ContractValidators.optionalStringArray(map, "methods", parent, ContractEnums.ReminderMethods)
        val methods = map["methods"]
        if (methods !is List<*> || methods.isEmpty()) {
            throw NativeContractViolation("$parent.methods must be a non-empty array.", "$parent.methods")
        }
        if (methods.toSet().size != methods.size) {
            throw NativeContractViolation("$parent.methods must not contain duplicates.", "$parent.methods")
        }
        ContractValidators.optionalInteger(map, "advance_minutes", parent)
        ContractValidators.optionalString(map, "message", parent)
        ContractValidators.requireBoolean(map, "is_enabled", parent)
        ContractValidators.requireEnum(map, "status", parent, ContractEnums.ReminderStatus)
        ContractValidators.optionalString(map, "scheduled_at", parent)
        ContractValidators.optionalString(map, "last_triggered_at", parent)
        ContractValidators.optionalString(map, "failure_reason", parent)
        ContractValidators.requireString(map, "created_at", parent, nonEmpty = true)
        ContractValidators.requireString(map, "updated_at", parent, nonEmpty = true)
        ContractValidators.optionalString(map, "deleted_at", parent)
    }
}
