package com.excellentcalendar.excellent_calendar.bridge.contract

/** Request and response validation for occurrence and recurring-series operations. */
internal object OccurrenceV2Contracts {
    private val identityFields = setOf(
        "event_id", "recurrence_revision", "occurrence_key", "occurrence_start_at", "occurrence_start_date",
    )

    fun list(arguments: Any?): V2JsonRequest =
        V2ContractPrimitives.request(arguments, "ListEventOccurrencesRequest") { map ->
            val allowed = setOf(
                "event_id", "recurrence_revision", "is_all_day", "range_start_at", "range_end_at",
                "range_start_date", "range_end_date", "cursor", "limit",
            )
            ContractValidators.rejectUnknownFields(map, allowed, "ListEventOccurrencesRequest")
            V2ContractPrimitives.requireFields(map, allowed, "ListEventOccurrencesRequest")
            ContractValidators.requireString(map, "event_id", "ListEventOccurrencesRequest", nonEmpty = true)
            V2ContractPrimitives.positiveInteger(map, "recurrence_revision", "ListEventOccurrencesRequest")
            ContractValidators.requireBoolean(map, "is_all_day", "ListEventOccurrencesRequest")
            V2ContractPrimitives.nullableString(map, "cursor", "ListEventOccurrencesRequest")
            V2ContractPrimitives.positiveInteger(
                map,
                "limit",
                "ListEventOccurrencesRequest",
                maximum = 200,
            )
            V2ContractPrimitives.validateExclusiveTimePair(
                isAllDay = map["is_all_day"] as Boolean,
                timed = listOf(map["range_start_at"], map["range_end_at"]),
                allDay = listOf(map["range_start_date"], map["range_end_date"]),
                parent = "ListEventOccurrencesRequest",
            )
        }

    fun operation(arguments: Any?): V2JsonRequest =
        V2ContractPrimitives.request(arguments, "EventOccurrenceOperationRequest") { map ->
            ContractValidators.rejectUnknownFields(map, identityFields, "EventOccurrenceOperationRequest")
            V2ContractPrimitives.requireFields(map, identityFields, "EventOccurrenceOperationRequest")
            ContractValidators.requireString(map, "event_id", "EventOccurrenceOperationRequest", nonEmpty = true)
            V2ContractPrimitives.positiveInteger(map, "recurrence_revision", "EventOccurrenceOperationRequest")
            ContractValidators.requireString(map, "occurrence_key", "EventOccurrenceOperationRequest", nonEmpty = true)
            V2ContractPrimitives.validateExactlyOneString(
                map["occurrence_start_at"],
                map["occurrence_start_date"],
                "EventOccurrenceOperationRequest",
            )
        }

    fun seriesOperation(arguments: Any?): V2JsonRequest =
        V2ContractPrimitives.request(arguments, "EventSeriesOperationRequest") { map ->
            ContractValidators.rejectUnknownFields(
                map,
                setOf("event_id", "recurrence_revision"),
                "EventSeriesOperationRequest",
            )
            ContractValidators.requireString(map, "event_id", "EventSeriesOperationRequest", nonEmpty = true)
            V2ContractPrimitives.positiveInteger(map, "recurrence_revision", "EventSeriesOperationRequest")
        }

    fun response(data: Any?) {
        val map = V2ContractPrimitives.objectMap(data, "EventOccurrenceResponse")
        V2ContractPrimitives.requireExactFields(
            map,
            setOf(
                "event_id", "recurrence_revision", "occurrence_key", "occurrence_start_at", "occurrence_end_at",
                "occurrence_start_date", "occurrence_end_date", "timezone", "state",
            ),
            "EventOccurrenceResponse",
        )
        ContractValidators.requireString(map, "event_id", "EventOccurrenceResponse", nonEmpty = true)
        ContractValidators.requireString(map, "occurrence_key", "EventOccurrenceResponse", nonEmpty = true)
        if (map["state"] != null) stateResponse(map["state"])
    }

    fun stateResponse(data: Any?) {
        val map = V2ContractPrimitives.objectMap(data, "EventOccurrenceStateResponse")
        V2ContractPrimitives.requireExactFields(
            map,
            setOf(
                "event_id", "recurrence_revision", "occurrence_key", "occurrence_start_at",
                "occurrence_start_date", "status", "state_changed_at", "reopened_at", "created_at", "updated_at",
            ),
            "EventOccurrenceStateResponse",
        )
        ContractValidators.requireEnum(
            map,
            "status",
            "EventOccurrenceStateResponse",
            setOf("scheduled", "completed", "skipped", "cancelled"),
        )
    }

    fun listResponse(data: Any?) {
        val map = V2ContractPrimitives.objectMap(data, "EventOccurrenceListResponse")
        V2ContractPrimitives.requireExactFields(
            map,
            setOf("items", "has_more", "next_cursor"),
            "EventOccurrenceListResponse",
        )
        val items = map["items"] as? List<*>
            ?: throw NativeContractViolation("items must be an array.", "data.items")
        if (items.size > 200) throw NativeContractViolation("items exceeds 200.", "data.items")
        items.forEach(::response)
    }
}
