package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec

/** Shared wire-format checks used by the module-specific Contract v2 adapters. */
internal object V2ContractPrimitives {
    fun request(
        arguments: Any?,
        parent: String,
        validator: (Map<String, Any?>) -> Unit,
    ): V2JsonRequest {
        val map = try {
            NativeContractJsonCodec.normalizeMap(arguments)
        } catch (error: IllegalArgumentException) {
            throw NativeContractViolation("$parent must be an object.", parent, error)
        }
        validator(map)
        return V2JsonRequest(map)
    }

    fun requireFields(map: Map<String, Any?>, fields: Set<String>, parent: String) {
        fields.firstOrNull { !map.containsKey(it) }
            ?.let { throw NativeContractViolation("$parent.$it is required.", "$parent.$it") }
    }

    fun nullableString(map: Map<String, Any?>, key: String, parent: String) {
        if (map[key] != null && map[key] !is String) {
            throw NativeContractViolation("$parent.$key must be string or null.", "$parent.$key")
        }
    }

    fun nullableNonBlankString(map: Map<String, Any?>, key: String, parent: String) {
        val value = map[key]
        if (value != null && (value !is String || value.isBlank())) {
            throw NativeContractViolation("$parent.$key must be a non-empty string or null.", "$parent.$key")
        }
    }

    fun nullableInteger(map: Map<String, Any?>, key: String, parent: String) {
        val value = map[key]
        if (value != null && value !is Int && value !is Long) {
            throw NativeContractViolation("$parent.$key must be integer or null.", "$parent.$key")
        }
    }

    fun positiveInteger(
        map: Map<String, Any?>,
        key: String,
        parent: String,
        minimum: Int = 1,
        maximum: Int? = null,
    ) {
        val value = integerValue(map[key])
            ?: throw NativeContractViolation("$parent.$key must be integer.", "$parent.$key")
        if (value < minimum || (maximum != null && value > maximum)) {
            throw NativeContractViolation("$parent.$key is out of range.", "$parent.$key")
        }
    }

    fun integerValue(value: Any?): Long? = when (value) {
        is Byte -> value.toLong()
        is Short -> value.toLong()
        is Int -> value.toLong()
        is Long -> value
        else -> null
    }

    fun validateExclusiveTimePair(
        isAllDay: Boolean,
        timed: List<Any?>,
        allDay: List<Any?>,
        parent: String,
    ) {
        val valid = if (isAllDay) {
            allDay.all { it is String && it.isNotBlank() } && timed.all { it == null }
        } else {
            timed.all { it is String && it.isNotBlank() } && allDay.all { it == null }
        }
        if (!valid) {
            throw NativeContractViolation(
                "$parent timed/all-day fields are mutually exclusive.",
                "$parent.is_all_day",
            )
        }
    }

    fun validateExactlyOneString(first: Any?, second: Any?, parent: String) {
        val valid = (first is String && first.isNotBlank() && second == null) ||
            (second is String && second.isNotBlank() && first == null)
        if (!valid) {
            throw NativeContractViolation(
                "$parent must carry exactly one planned occurrence start.",
                "$parent.occurrence_start_at",
            )
        }
    }

    @Suppress("UNCHECKED_CAST")
    fun objectMap(data: Any?, parent: String): Map<String, Any?> =
        data as? Map<String, Any?> ?: throw NativeContractViolation("$parent must be an object.", "data")

    fun requireExactFields(map: Map<String, Any?>, fields: Set<String>, parent: String) {
        ContractValidators.rejectUnknownFields(map, fields, parent)
        requireFields(map, fields, parent)
    }
}
