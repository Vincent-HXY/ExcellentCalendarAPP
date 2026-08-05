package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import java.time.Instant
import java.time.LocalDateTime
import java.time.format.DateTimeParseException

object RuntimeTimezoneRequestContracts {
    fun resolveLocalDateTime(arguments: Any?): V2JsonRequest = request(
        arguments,
        parent = "ResolveLocalDateTimeRequest",
        allowed = setOf("local_datetime", "timezone"),
    ) { map ->
        requireLocalDateTime(map, "local_datetime", "ResolveLocalDateTimeRequest")
        requireTimezone(map, "ResolveLocalDateTimeRequest")
    }

    fun localizeInstants(arguments: Any?): V2JsonRequest = request(
        arguments,
        parent = "LocalizeInstantsRequest",
        allowed = setOf("timezone", "instants"),
    ) { map ->
        requireTimezone(map, "LocalizeInstantsRequest")
        val instants = map["instants"] as? List<*>
            ?: throw NativeContractViolation(
                "LocalizeInstantsRequest.instants must be an array.",
                "LocalizeInstantsRequest.instants",
            )
        if (instants.isEmpty() || instants.size > MaxBatchSize) {
            throw NativeContractViolation(
                "LocalizeInstantsRequest.instants must contain 1 to $MaxBatchSize values.",
                "LocalizeInstantsRequest.instants",
            )
        }
        instants.forEachIndexed { index, value ->
            requireUtcInstant(value, "LocalizeInstantsRequest.instants[$index]")
        }
    }

    private fun request(
        arguments: Any?,
        parent: String,
        allowed: Set<String>,
        validate: (Map<String, Any?>) -> Unit,
    ): V2JsonRequest {
        val map = try {
            NativeContractJsonCodec.normalizeMap(arguments)
        } catch (error: IllegalArgumentException) {
            throw NativeContractViolation("$parent must be an object.", parent, error)
        }
        ContractValidators.rejectUnknownFields(map, allowed, parent)
        validate(map)
        return V2JsonRequest(map)
    }
}

object RuntimeTimezoneResponseContracts {
    fun deviceTimezone(data: Any?) {
        val map = objectMap(data, "DeviceTimezoneResponse")
        requireExactFields(map, setOf("timezone"), "DeviceTimezoneResponse")
        requireTimezone(map, "DeviceTimezoneResponse")
    }

    fun resolveLocalDateTime(
        data: Any?,
        expectedLocalDateTime: String,
        expectedTimezone: String,
    ) {
        val parent = "ResolveLocalDateTimeResponse"
        val map = objectMap(data, parent)
        requireExactFields(
            map,
            setOf(
                "requested_local_datetime",
                "resolved_local_datetime",
                "utc_instant",
                "timezone",
                "resolution",
            ),
            parent,
        )
        requireLocalDateTime(map, "requested_local_datetime", parent)
        requireLocalDateTime(map, "resolved_local_datetime", parent)
        requireUtcInstant(map["utc_instant"], "$parent.utc_instant")
        requireTimezone(map, parent)
        ContractValidators.requireEnum(
            map,
            "resolution",
            parent,
            setOf("exact", "gap_shifted", "fold_earlier"),
        )
        if (map["requested_local_datetime"] != expectedLocalDateTime || map["timezone"] != expectedTimezone) {
            throw NativeContractViolation(
                "$parent does not correspond to its request.",
                parent,
            )
        }
        if (map["resolution"] != "gap_shifted" &&
            map["resolved_local_datetime"] != expectedLocalDateTime
        ) {
            throw NativeContractViolation(
                "$parent.resolved_local_datetime is inconsistent with resolution.",
                "$parent.resolved_local_datetime",
            )
        }
    }

    fun localizeInstants(
        data: Any?,
        expectedTimezone: String,
        expectedInstants: List<String>,
    ) {
        val parent = "LocalizeInstantsResponse"
        val map = objectMap(data, parent)
        requireExactFields(map, setOf("timezone", "items"), parent)
        requireTimezone(map, parent)
        if (map["timezone"] != expectedTimezone) {
            throw NativeContractViolation("$parent.timezone does not match its request.", "$parent.timezone")
        }
        val items = map["items"] as? List<*>
            ?: throw NativeContractViolation("$parent.items must be an array.", "$parent.items")
        if (items.size != expectedInstants.size || items.isEmpty() || items.size > MaxBatchSize) {
            throw NativeContractViolation("$parent.items has an invalid size.", "$parent.items")
        }
        items.forEachIndexed { index, item ->
            val itemParent = "$parent.items[$index]"
            val itemMap = objectMap(item, itemParent)
            requireExactFields(itemMap, setOf("instant", "local_datetime"), itemParent)
            requireUtcInstant(itemMap["instant"], "$itemParent.instant")
            requireLocalDateTime(itemMap, "local_datetime", itemParent)
            if (itemMap["instant"] != expectedInstants[index]) {
                throw NativeContractViolation(
                    "$itemParent.instant does not preserve request order.",
                    "$itemParent.instant",
                )
            }
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun objectMap(data: Any?, parent: String): Map<String, Any?> =
        data as? Map<String, Any?>
            ?: throw NativeContractViolation("$parent must be an object.", parent)

    private fun requireExactFields(map: Map<String, Any?>, fields: Set<String>, parent: String) {
        ContractValidators.rejectUnknownFields(map, fields, parent)
        fields.firstOrNull { !map.containsKey(it) }?.let {
            throw NativeContractViolation("$parent.$it is required.", "$parent.$it")
        }
    }
}

internal const val MaxBatchSize = 400
private val LocalDateTimePattern = Regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}$")
private val UtcInstantPattern = Regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")

private fun requireTimezone(map: Map<String, Any?>, parent: String) {
    ContractValidators.requireString(map, "timezone", parent, nonEmpty = true)
    val timezone = map["timezone"] as String
    if (timezone.length > 255) {
        throw NativeContractViolation("$parent.timezone is too long.", "$parent.timezone")
    }
}

private fun requireLocalDateTime(map: Map<String, Any?>, key: String, parent: String) {
    ContractValidators.requireString(map, key, parent, nonEmpty = true)
    val value = map[key] as String
    if (!LocalDateTimePattern.matches(value)) {
        throw NativeContractViolation("$parent.$key is not a whole-second local date-time.", "$parent.$key")
    }
    try {
        LocalDateTime.parse(value)
    } catch (error: DateTimeParseException) {
        throw NativeContractViolation("$parent.$key is not a valid local date-time.", "$parent.$key", error)
    }
}

private fun requireUtcInstant(value: Any?, field: String) {
    if (value !is String || !UtcInstantPattern.matches(value)) {
        throw NativeContractViolation("$field is not a whole-second UTC instant.", field)
    }
    try {
        Instant.parse(value)
    } catch (error: DateTimeParseException) {
        throw NativeContractViolation("$field is not a valid UTC instant.", field, error)
    }
}
