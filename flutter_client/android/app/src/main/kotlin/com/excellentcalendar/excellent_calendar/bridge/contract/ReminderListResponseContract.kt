package com.excellentcalendar.excellent_calendar.bridge.contract

object ReminderListResponseContract {
    fun validate(data: Any?) {
        if (data !is Map<*, *>) {
            throw NativeContractViolation("ReminderListResponse data must be an object.", "data")
        }
        @Suppress("UNCHECKED_CAST")
        val map = data as Map<String, Any?>
        ContractValidators.rejectUnknownFields(map, setOf("items", "pagination"), "ReminderListResponse")

        val items = map["items"]
        if (items !is List<*>) {
            throw NativeContractViolation("ReminderListResponse.items must be an array.", "data.items")
        }
        items.forEachIndexed { index, item ->
            if (item !is Map<*, *>) {
                throw NativeContractViolation(
                    "ReminderListResponse.items item must be an object.",
                    "data.items[$index]",
                )
            }
            @Suppress("UNCHECKED_CAST")
            ReminderResponseContract.validateMap(item as Map<String, Any?>, "ReminderListResponse.items[$index]")
        }

        val pagination = map["pagination"]
        if (pagination !is Map<*, *>) {
            throw NativeContractViolation("ReminderListResponse.pagination must be an object.", "data.pagination")
        }
        @Suppress("UNCHECKED_CAST")
        validatePagination(pagination as Map<String, Any?>)
    }

    fun findReminder(data: Any?, reminderId: String): ReminderContract? {
        validate(data)
        @Suppress("UNCHECKED_CAST")
        val map = data as Map<String, Any?>
        @Suppress("UNCHECKED_CAST")
        val items = map["items"] as List<Map<String, Any?>>
        val item = items.firstOrNull { it["id"] == reminderId } ?: return null
        return ReminderContract.fromData(item)
    }

    private fun validatePagination(map: Map<String, Any?>) {
        val parent = "ReminderListResponse.pagination"
        ContractValidators.rejectUnknownFields(
            map,
            setOf("total", "page", "page_size", "has_more", "next_cursor"),
            parent,
        )
        if (!map.containsKey("total")) {
            throw NativeContractViolation("$parent.total is required.", "$parent.total")
        }
        if (!map.containsKey("page")) {
            throw NativeContractViolation("$parent.page is required.", "$parent.page")
        }
        ContractValidators.optionalInteger(map, "total", parent)
        ContractValidators.optionalInteger(map, "page", parent)
        ContractValidators.requireInteger(map, "page_size", parent)
        ContractValidators.requireBoolean(map, "has_more", parent)
        if (!map.containsKey("next_cursor")) {
            throw NativeContractViolation("$parent.next_cursor is required.", "$parent.next_cursor")
        }
        ContractValidators.optionalString(map, "next_cursor", parent)
    }
}
