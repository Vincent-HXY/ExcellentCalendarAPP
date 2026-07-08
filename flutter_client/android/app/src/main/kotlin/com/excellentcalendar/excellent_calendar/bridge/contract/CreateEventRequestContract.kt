package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec

/**
 * 创建事件请求合约。
 *
 * `data class` 是 Kotlin 专门用于承载数据的类，会自动生成 `equals`、`hashCode`、
 * `toString`、`copy` 等方法。这里实际只保存规范化后的 payload。
 *
 * `payload: Map<String, Any?>` 表示字段名到任意 JSON 值的映射；使用 Map 是为了尽量贴近
 * Dart/C++ 的 JSON 协议，避免 Kotlin 层和 C++ 层维护两套实体类。
 */
data class CreateEventRequestContract(
    private val payload: Map<String, Any?>,
) {
    /** 给 C++ 使用的 JSON 字符串。 */
    fun toJson(): String = NativeContractJsonCodec.encodeObject(payload)

    /** 给测试或上层直接检查用的 Map 视图。 */
    fun toMap(): Map<String, Any?> = payload

    /**
     * `companion object` 类似 Java static 区域，适合放工厂方法和常量。
     * 外部调用方式是 `CreateEventRequestContract.fromMethodArguments(arguments)`。
     */
    companion object {
        /** 允许 Dart 传入的字段白名单；不在这里的字段都会被拒绝。 */
        private val AllowedFields = setOf(
            "title",
            "content",
            "start_at",
            "end_at",
            "is_all_day",
            "category_id",
            "importance",
            "location",
            "timezone",
            "source",
            "recurrence",
            "reminders",
        )

        /** 从 Flutter MethodChannel 的原始 arguments 构造并校验请求对象。 */
        fun fromMethodArguments(arguments: Any?): CreateEventRequestContract {
            val map = try {
                NativeContractJsonCodec.normalizeMap(arguments)
            } catch (error: IllegalArgumentException) {
                throw NativeContractViolation(error.message ?: "Invalid MethodChannel arguments.", cause = error)
            }
            validate(map)
            return CreateEventRequestContract(map)
        }

        /** 校验创建事件的基本字段、枚举字段、递归规则和提醒草稿。 */
        private fun validate(map: Map<String, Any?>) {
            ContractValidators.rejectUnknownFields(map, AllowedFields, "CreateEventRequest")
            ContractValidators.requireString(map, "title", "CreateEventRequest", nonEmpty = true)
            ContractValidators.optionalString(map, "content", "CreateEventRequest")
            ContractValidators.requireString(map, "start_at", "CreateEventRequest", nonEmpty = true)
            ContractValidators.requireString(map, "end_at", "CreateEventRequest", nonEmpty = true)
            ContractValidators.requireBoolean(map, "is_all_day", "CreateEventRequest")
            ContractValidators.optionalString(map, "category_id", "CreateEventRequest")
            ContractValidators.optionalEnum(
                map,
                "importance",
                "CreateEventRequest",
                ContractEnums.Importance,
            )
            ContractValidators.optionalString(map, "location", "CreateEventRequest")
            ContractValidators.optionalString(map, "timezone", "CreateEventRequest")
            ContractValidators.requireEnum(
                map,
                "source",
                "CreateEventRequest",
                ContractEnums.CreateEventSource,
            )
            ContractValidators.optionalObject(map, "recurrence", "CreateEventRequest")?.let {
                validateRecurrenceRule(it, "CreateEventRequest.recurrence")
            }
            ContractValidators.optionalObjectArray(map, "reminders", "CreateEventRequest").forEachIndexed { index, reminder ->
                validateReminderDraft(reminder, "CreateEventRequest.reminders[$index]")
            }
        }

        /** 校验 recurrence 子对象；当前 C++ 阶段会识别字段，但业务持久化尚未实现。 */
        private fun validateRecurrenceRule(map: Map<String, Any?>, parent: String) {
            ContractValidators.rejectUnknownFields(
                map,
                setOf(
                    "frequency",
                    "interval",
                    "days_of_week",
                    "day_of_month",
                    "month_of_year",
                    "start_at",
                    "end_at",
                    "count",
                    "timezone",
                    "rrule",
                ),
                parent,
            )
            ContractValidators.requireEnum(map, "frequency", parent, ContractEnums.RecurrenceFrequency)
            ContractValidators.requireInteger(map, "interval", parent)
            val daysOfWeek = map["days_of_week"]
            if (daysOfWeek != null) {
                if (daysOfWeek !is List<*>) {
                    throw NativeContractViolation("$parent.days_of_week must be an array.", "$parent.days_of_week")
                }
                daysOfWeek.forEachIndexed { index, value ->
                    if (value !is Int && value !is Long) {
                        throw NativeContractViolation(
                            "$parent.days_of_week item must be integer.",
                            "$parent.days_of_week[$index]",
                        )
                    }
                }
            }
            ContractValidators.optionalInteger(map, "day_of_month", parent)
            ContractValidators.optionalInteger(map, "month_of_year", parent)
            ContractValidators.requireString(map, "start_at", parent, nonEmpty = true)
            ContractValidators.optionalString(map, "end_at", parent)
            ContractValidators.optionalInteger(map, "count", parent)
            if (!map.containsKey("timezone")) {
                throw NativeContractViolation("$parent.timezone is required.", "$parent.timezone")
            }
            ContractValidators.optionalString(map, "timezone", parent)
            ContractValidators.optionalString(map, "rrule", parent)
        }

        /** 校验 reminders 数组中的单个提醒草稿。 */
        private fun validateReminderDraft(map: Map<String, Any?>, parent: String) {
            ContractValidators.rejectUnknownFields(
                map,
                setOf(
                    "target_type",
                    "target_id",
                    "remind_at",
                    "advance_minutes",
                    "methods",
                    "message",
                    "is_enabled",
                    "source",
                ),
                parent,
            )
            ContractValidators.requireEnum(map, "target_type", parent, setOf("event", "anniversary"))
            ContractValidators.optionalString(map, "target_id", parent)
            ContractValidators.optionalString(map, "remind_at", parent)
            ContractValidators.optionalInteger(map, "advance_minutes", parent)
            val remindAt = map["remind_at"]
            val advanceMinutes = map["advance_minutes"]
            if (remindAt == null && advanceMinutes == null) {
                throw NativeContractViolation(
                    "$parent requires remind_at or advance_minutes.",
                    "$parent.remind_at",
                )
            }
            when (advanceMinutes) {
                is Int -> if (advanceMinutes < 0) {
                    throw NativeContractViolation(
                        "$parent.advance_minutes must be greater than or equal to 0.",
                        "$parent.advance_minutes",
                    )
                }
                is Long -> if (advanceMinutes < 0L) {
                    throw NativeContractViolation(
                        "$parent.advance_minutes must be greater than or equal to 0.",
                        "$parent.advance_minutes",
                    )
                }
            }
            ContractValidators.optionalStringArray(map, "methods", parent, ContractEnums.ReminderMethods)
            val methods = map["methods"]
            if (methods !is List<*> || methods.isEmpty()) {
                throw NativeContractViolation("$parent.methods must be a non-empty array.", "$parent.methods")
            }
            if (methods.toSet().size != methods.size) {
                throw NativeContractViolation("$parent.methods must not contain duplicates.", "$parent.methods")
            }
            ContractValidators.optionalString(map, "message", parent)
            ContractValidators.requireBoolean(map, "is_enabled", parent)
            ContractValidators.requireEnum(map, "source", parent, ContractEnums.ReminderSource)
        }
    }
}
