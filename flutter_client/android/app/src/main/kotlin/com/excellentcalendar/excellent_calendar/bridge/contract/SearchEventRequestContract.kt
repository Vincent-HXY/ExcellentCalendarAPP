package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec

data class SearchEventRequestContract(
    private val payload: Map<String, Any?>,
) {
    fun toJson(): String = NativeContractJsonCodec.encodeObject(payload)

    fun toMap(): Map<String, Any?> = payload

    companion object {
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

        fun fromMethodArguments(arguments: Any?): SearchEventRequestContract {
            val map = try {
                NativeContractJsonCodec.normalizeMap(arguments)
            } catch (error: IllegalArgumentException) {
                throw NativeContractViolation(error.message ?: "Invalid MethodChannel arguments.", cause = error)
            }
            validate(map)
            return SearchEventRequestContract(map)
        }

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
