package com.excellentcalendar.excellent_calendar.bridge.contract

internal object ContractEnums {
    val Importance = setOf(
        "unimportant_noturgent",
        "important_noturgent",
        "unimportant_urgent",
        "important_urgent",
    )
    val CreateEventSource = setOf("manual", "ai_extraction", "sync", "import", "wechat")
    val ReminderSource = setOf("manual", "auto", "ai_extraction", "sync", "import", "wechat")
    val ReminderMethods = setOf("ring", "popup", "wechat")
    val RecurrenceFrequency = setOf("daily", "weekly", "monthly", "yearly", "custom")
    val SortDirection = setOf("asc", "desc")
    val EventSortBy = setOf("start_at", "created_at", "updated_at", "importance", "title")
}

internal object ContractValidators {
    fun rejectUnknownFields(
        map: Map<String, Any?>,
        allowed: Set<String>,
        parent: String,
    ) {
        val unknown = map.keys.firstOrNull { it !in allowed }
        if (unknown != null) {
            throw NativeContractViolation("$parent contains an unknown field.", "$parent.$unknown")
        }
    }

    fun requireString(
        map: Map<String, Any?>,
        key: String,
        parent: String,
        nonEmpty: Boolean = false,
    ) {
        if (!map.containsKey(key)) {
            throw NativeContractViolation("$parent.$key is required.", "$parent.$key")
        }
        val value = map[key]
        if (value !is String || (nonEmpty && value.isBlank())) {
            throw NativeContractViolation("$parent.$key must be a string.", "$parent.$key")
        }
    }

    fun optionalString(map: Map<String, Any?>, key: String, parent: String) {
        val value = map[key]
        if (value != null && value !is String) {
            throw NativeContractViolation("$parent.$key must be a string or null.", "$parent.$key")
        }
    }

    fun requireBoolean(map: Map<String, Any?>, key: String, parent: String) {
        if (!map.containsKey(key)) {
            throw NativeContractViolation("$parent.$key is required.", "$parent.$key")
        }
        if (map[key] !is Boolean) {
            throw NativeContractViolation("$parent.$key must be boolean.", "$parent.$key")
        }
    }

    fun optionalBoolean(map: Map<String, Any?>, key: String, parent: String) {
        val value = map[key]
        if (value != null && value !is Boolean) {
            throw NativeContractViolation("$parent.$key must be boolean or null.", "$parent.$key")
        }
    }

    fun requireInteger(map: Map<String, Any?>, key: String, parent: String) {
        if (!map.containsKey(key)) {
            throw NativeContractViolation("$parent.$key is required.", "$parent.$key")
        }
        if (map[key] !is Int && map[key] !is Long) {
            throw NativeContractViolation("$parent.$key must be integer.", "$parent.$key")
        }
    }

    fun optionalInteger(map: Map<String, Any?>, key: String, parent: String) {
        val value = map[key]
        if (value != null && value !is Int && value !is Long) {
            throw NativeContractViolation("$parent.$key must be integer or null.", "$parent.$key")
        }
    }

    fun optionalEnum(
        map: Map<String, Any?>,
        key: String,
        parent: String,
        allowed: Set<String>,
    ) {
        val value = map[key]
        if (value != null && (value !is String || value !in allowed)) {
            throw NativeContractViolation("$parent.$key has an unsupported enum value.", "$parent.$key")
        }
    }

    fun requireEnum(
        map: Map<String, Any?>,
        key: String,
        parent: String,
        allowed: Set<String>,
    ) {
        requireString(map, key, parent, nonEmpty = true)
        val value = map[key] as String
        if (value !in allowed) {
            throw NativeContractViolation("$parent.$key has an unsupported enum value.", "$parent.$key")
        }
    }

    fun optionalStringArray(
        map: Map<String, Any?>,
        key: String,
        parent: String,
        allowed: Set<String>? = null,
    ) {
        val value = map[key] ?: return
        if (value !is List<*>) {
            throw NativeContractViolation("$parent.$key must be an array.", "$parent.$key")
        }
        value.forEachIndexed { index, item ->
            if (item !is String || (allowed != null && item !in allowed)) {
                throw NativeContractViolation("$parent.$key item has an unsupported value.", "$parent.$key[$index]")
            }
        }
    }

    fun optionalObject(map: Map<String, Any?>, key: String, parent: String): Map<String, Any?>? {
        val value = map[key] ?: return null
        if (value !is Map<*, *>) {
            throw NativeContractViolation("$parent.$key must be an object or null.", "$parent.$key")
        }
        @Suppress("UNCHECKED_CAST")
        return value as Map<String, Any?>
    }

    fun optionalObjectArray(map: Map<String, Any?>, key: String, parent: String): List<Map<String, Any?>> {
        val value = map[key] ?: return emptyList()
        if (value !is List<*>) {
            throw NativeContractViolation("$parent.$key must be an array.", "$parent.$key")
        }
        return value.mapIndexed { index, item ->
            if (item !is Map<*, *>) {
                throw NativeContractViolation("$parent.$key item must be an object.", "$parent.$key[$index]")
            }
            @Suppress("UNCHECKED_CAST")
            item as Map<String, Any?>
        }
    }
}
