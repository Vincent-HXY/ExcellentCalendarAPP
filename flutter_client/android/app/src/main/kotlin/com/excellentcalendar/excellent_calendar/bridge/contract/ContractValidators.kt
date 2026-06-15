package com.excellentcalendar.excellent_calendar.bridge.contract

/**
 * Kotlin 层声明的枚举字符串集合。
 *
 * 这里没有用 Kotlin `enum class`，是因为跨语言边界最终传输的是字符串。
 * 用 `Set<String>` 可以直接检查 JSON 字段值是否属于协议允许范围。
 */
internal object ContractEnums {
    val EventStatus = setOf("active", "completed", "cancelled", "archived")
    val EventOccurrenceStatus = setOf("completed", "skipped", "cancelled")
    val Importance = setOf(
        "unimportant_noturgent",
        "important_noturgent",
        "unimportant_urgent",
        "important_urgent",
    )
    val CreateEventSource = setOf("manual", "ai_extraction", "sync", "import", "wechat")
    val ReminderSource = setOf("manual", "auto", "ai_extraction", "sync", "import", "wechat")
    val ReminderMethods = setOf("ring", "popup", "wechat")
    val ReminderStatus = setOf("pending", "scheduled", "sent", "failed", "cancelled")
    val RecurrenceFrequency = setOf("daily", "weekly", "monthly", "yearly", "custom")
    val SortDirection = setOf("asc", "desc")
    val EventSortBy = setOf("start_at", "created_at", "updated_at", "importance", "title")
}

/**
 * 合约校验工具。
 *
 * `internal` 表示只在当前 Gradle module 内可见，外部模块不能直接访问。
 * 这些函数都不返回业务值：通过就安静结束，不通过就抛出 `NativeContractViolation`。
 */
internal object ContractValidators {
    /** 拒绝未知字段，防止 Dart 传入拼错字段却被静默忽略。 */
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

    /** 要求字段存在且为 String；`nonEmpty=true` 时还要求不能全是空白。 */
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

    /** 可选字符串：字段缺失或 null 都可以；非 null 时必须是 String。 */
    fun optionalString(map: Map<String, Any?>, key: String, parent: String) {
        val value = map[key]
        if (value != null && value !is String) {
            throw NativeContractViolation("$parent.$key must be a string or null.", "$parent.$key")
        }
    }

    /** 必填布尔值。Kotlin 的 `is Boolean` 是运行时类型检查。 */
    fun requireBoolean(map: Map<String, Any?>, key: String, parent: String) {
        if (!map.containsKey(key)) {
            throw NativeContractViolation("$parent.$key is required.", "$parent.$key")
        }
        if (map[key] !is Boolean) {
            throw NativeContractViolation("$parent.$key must be boolean.", "$parent.$key")
        }
    }

    /** 可选布尔值。 */
    fun optionalBoolean(map: Map<String, Any?>, key: String, parent: String) {
        val value = map[key]
        if (value != null && value !is Boolean) {
            throw NativeContractViolation("$parent.$key must be boolean or null.", "$parent.$key")
        }
    }

    /** 必填整数。MethodChannel/JSON 可能给 Int 或 Long，所以两种都接受。 */
    fun requireInteger(map: Map<String, Any?>, key: String, parent: String) {
        if (!map.containsKey(key)) {
            throw NativeContractViolation("$parent.$key is required.", "$parent.$key")
        }
        if (map[key] !is Int && map[key] !is Long) {
            throw NativeContractViolation("$parent.$key must be integer.", "$parent.$key")
        }
    }

    /** 可选整数。 */
    fun optionalInteger(map: Map<String, Any?>, key: String, parent: String) {
        val value = map[key]
        if (value != null && value !is Int && value !is Long) {
            throw NativeContractViolation("$parent.$key must be integer or null.", "$parent.$key")
        }
    }

    /** 可选枚举字符串：缺失/null 可以，非 null 时必须在 allowed 集合中。 */
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

    /** 必填枚举字符串：先复用 requireString，再检查值域。 */
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

    /** 可选字符串数组；如果传入 allowed，则数组每一项都必须在允许集合里。 */
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

    /**
     * 可选对象字段。
     *
     * `@Suppress("UNCHECKED_CAST")` 是因为 JVM 运行时无法完整验证泛型里的 String/Any?，
     * 但前面已经检查了顶层是 Map，因此在这个边界内接受这次转换。
     */
    fun optionalObject(map: Map<String, Any?>, key: String, parent: String): Map<String, Any?>? {
        val value = map[key] ?: return null
        if (value !is Map<*, *>) {
            throw NativeContractViolation("$parent.$key must be an object or null.", "$parent.$key")
        }
        @Suppress("UNCHECKED_CAST")
        return value as Map<String, Any?>
    }

    /** 可选对象数组，常用于 reminders 这种“数组里每一项都是对象”的字段。 */
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
