package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec

data class ListRemindersRequestContract(
    private val payload: Map<String, Any?>,
) {
    fun toJson(): String = NativeContractJsonCodec.encodeObject(payload)

    fun toMap(): Map<String, Any?> = payload

    companion object {
        private val AllowedFields = setOf(
            "target_type",
            "target_id",
            "remind_at_from",
            "remind_at_to",
            "methods",
            "status",
            "is_enabled",
            "include_deleted",
            "pagination",
            "sort_by",
            "sort_direction",
        )

        fun fromMethodArguments(arguments: Any?): ListRemindersRequestContract {
            val map = try {
                NativeContractJsonCodec.normalizeMap(arguments)
            } catch (error: IllegalArgumentException) {
                throw NativeContractViolation(error.message ?: "Invalid MethodChannel arguments.", cause = error)
            }
            validate(map)
            return ListRemindersRequestContract(map)
        }

        private fun validate(map: Map<String, Any?>) {
            val parent = "ListRemindersRequest"
            ContractValidators.rejectUnknownFields(map, AllowedFields, parent)
            ContractValidators.optionalEnum(map, "target_type", parent, ContractEnums.ReminderTargetType)
            ContractValidators.optionalString(map, "target_id", parent)
            ContractValidators.optionalString(map, "remind_at_from", parent)
            ContractValidators.optionalString(map, "remind_at_to", parent)
            ContractValidators.optionalStringArray(map, "methods", parent, ContractEnums.ReminderMethods)
            ContractValidators.optionalStringArray(map, "status", parent, ContractEnums.ReminderStatus)
            ContractValidators.optionalBoolean(map, "is_enabled", parent)
            if (map.containsKey("include_deleted")) {
                ContractValidators.requireBoolean(map, "include_deleted", parent)
            }
            ContractValidators.optionalEnum(map, "sort_by", parent, ContractEnums.ReminderSortBy)
            ContractValidators.optionalEnum(map, "sort_direction", parent, ContractEnums.SortDirection)
            validatePagination(map, parent)
        }

        private fun validatePagination(map: Map<String, Any?>, parent: String) {
            if (!map.containsKey("pagination")) {
                return
            }
            val value = map["pagination"]
            if (value == null) {
                throw NativeContractViolation("$parent.pagination must be an object.", "$parent.pagination")
            }
            if (value !is Map<*, *>) {
                throw NativeContractViolation("$parent.pagination must be an object.", "$parent.pagination")
            }
            @Suppress("UNCHECKED_CAST")
            val pagination = value as Map<String, Any?>
            val paginationParent = "$parent.pagination"
            ContractValidators.rejectUnknownFields(
                pagination,
                setOf("page", "page_size", "cursor", "sort_by", "sort_direction"),
                paginationParent,
            )
            ContractValidators.optionalInteger(pagination, "page", paginationParent)
            ContractValidators.optionalInteger(pagination, "page_size", paginationParent)
            requireAtLeastOneIfPresent(pagination, "page", paginationParent)
            requireAtLeastOneIfPresent(pagination, "page_size", paginationParent)
            ContractValidators.optionalString(pagination, "cursor", paginationParent)
            ContractValidators.optionalEnum(pagination, "sort_by", paginationParent, ContractEnums.ReminderSortBy)
            ContractValidators.optionalEnum(pagination, "sort_direction", paginationParent, ContractEnums.SortDirection)
        }

        private fun requireAtLeastOneIfPresent(map: Map<String, Any?>, key: String, parent: String) {
            val value = map[key] ?: return
            val valid = when (value) {
                is Int -> value >= 1
                is Long -> value >= 1L
                else -> true
            }
            if (!valid) {
                throw NativeContractViolation("$parent.$key must be >= 1.", "$parent.$key")
            }
        }
    }
}
