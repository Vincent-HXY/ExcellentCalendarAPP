package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec

/**
 * 搜索事件请求合约。
 *
 * 搜索条件大多是可选字段，所以 payload 里允许很多字段为 null 或缺失。
 * Kotlin 层只负责校验“形状和值域”，真正的过滤、排序、分页由 C++ `EventService` 完成。
 */
data class SearchEventRequestContract(
    private val payload: Map<String, Any?>,
) {
    /** 转成 JSON 后传给 C++。 */
    fun toJson(): String = NativeContractJsonCodec.encodeObject(payload)

    /** 返回原始 Map，主要给测试使用。 */
    fun toMap(): Map<String, Any?> = payload

    companion object {
        /** 搜索请求允许的顶层字段。 */
        private val AllowedFields = setOf(
            "keyword",
            "start_at_from",
            "start_at_to",
            "category_ids",
            "importance",
            "location",
            "has_recurrence",
            "source",
            "include_deleted",
            "pagination",
            "sort_by",
            "sort_direction",
        )

        /** 从 MethodChannel arguments 构造搜索请求，失败时抛出 NativeContractViolation。 */
        fun fromMethodArguments(arguments: Any?): SearchEventRequestContract {
            val map = try {
                NativeContractJsonCodec.normalizeMap(arguments)
            } catch (error: IllegalArgumentException) {
                throw NativeContractViolation(error.message ?: "Invalid MethodChannel arguments.", cause = error)
            }
            validate(map)
            return SearchEventRequestContract(map)
        }

        /** 校验搜索条件，包括数组、布尔值、分页对象、排序字段等。 */
        private fun validate(map: Map<String, Any?>) {
            ContractValidators.rejectUnknownFields(map, AllowedFields, "SearchEventRequest")
            ContractValidators.optionalString(map, "keyword", "SearchEventRequest")
            ContractValidators.optionalString(map, "start_at_from", "SearchEventRequest")
            ContractValidators.optionalString(map, "start_at_to", "SearchEventRequest")
            ContractValidators.optionalStringArray(map, "category_ids", "SearchEventRequest")
            ContractValidators.optionalStringArray(
                map,
                "importance",
                "SearchEventRequest",
                ContractEnums.Importance,
            )
            ContractValidators.optionalString(map, "location", "SearchEventRequest")
            ContractValidators.optionalBoolean(map, "has_recurrence", "SearchEventRequest")
            ContractValidators.optionalStringArray(
                map,
                "source",
                "SearchEventRequest",
                ContractEnums.CreateEventSource,
            )
            ContractValidators.optionalBoolean(map, "include_deleted", "SearchEventRequest")
            ContractValidators.optionalObject(map, "pagination", "SearchEventRequest")?.let {
                validatePaginationRequest(it)
            }
            ContractValidators.optionalEnum(
                map,
                "sort_by",
                "SearchEventRequest",
                ContractEnums.EventSortBy,
            )
            ContractValidators.optionalEnum(
                map,
                "sort_direction",
                "SearchEventRequest",
                ContractEnums.SortDirection,
            )
        }

        /** 校验 pagination 子对象。cursor 字段目前只做合约识别，C++ 阶段会返回未实现。 */
        private fun validatePaginationRequest(map: Map<String, Any?>) {
            val parent = "SearchEventRequest.pagination"
            ContractValidators.rejectUnknownFields(
                map,
                setOf("page", "page_size", "cursor", "sort_by", "sort_direction"),
                parent,
            )
            ContractValidators.optionalInteger(map, "page", parent)
            ContractValidators.optionalInteger(map, "page_size", parent)
            ContractValidators.optionalString(map, "cursor", parent)
            ContractValidators.optionalString(map, "sort_by", parent)
            ContractValidators.optionalEnum(map, "sort_direction", parent, ContractEnums.SortDirection)
        }
    }
}
