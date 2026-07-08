package com.excellentcalendar.excellent_calendar.bridge.contract

/**
 * 事件列表响应合约。
 *
 * 搜索接口返回的 data 应包含：
 * - `items`：事件数组，每一项都必须符合 EventResponse。
 * - `pagination`：分页信息。
 */
object EventListResponseContract {
    /** 校验搜索响应 data 的整体结构。 */
    fun validate(data: Any?) {
        if (data !is Map<*, *>) {
            throw NativeContractViolation("EventListResponse data must be an object.", "data")
        }
        @Suppress("UNCHECKED_CAST")
        val map = data as Map<String, Any?>
        ContractValidators.rejectUnknownFields(map, setOf("items", "pagination"), "EventListResponse")

        val items = map["items"]
        if (items !is List<*>) {
            throw NativeContractViolation("EventListResponse.items must be an array.", "data.items")
        }
        items.forEachIndexed { index, item ->
            if (item !is Map<*, *>) {
                throw NativeContractViolation(
                    "EventListResponse.items item must be an object.",
                    "data.items[$index]",
                )
            }
            @Suppress("UNCHECKED_CAST")
            EventResponseContract.validateMap(item as Map<String, Any?>, "EventListResponse.items[$index]")
        }

        val pagination = map["pagination"]
        if (pagination !is Map<*, *>) {
            throw NativeContractViolation("EventListResponse.pagination must be an object.", "data.pagination")
        }
        @Suppress("UNCHECKED_CAST")
        validatePagination(pagination as Map<String, Any?>)
    }

    /** 校验分页对象。 */
    private fun validatePagination(map: Map<String, Any?>) {
        val parent = "EventListResponse.pagination"
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
