package com.excellentcalendar.excellent_calendar.bridge.contract

/**
 * 单个事件响应的合约校验器。
 *
 * C++ 返回 JSON 后，Kotlin 并不盲目信任它，而是在回 Dart 前再次校验字段。
 * 这样 native 层如果改坏了返回格式，问题会被转换成明确的 CONTRACT_VALIDATION_FAILED。
 */
object EventResponseContract {
    /** EventResponse 允许出现的字段集合。 */
    private val AllowedFields = setOf(
        "id",
        "title",
        "content",
        "start_at",
        "end_at",
        "is_all_day",
        "has_recurrence",
        "status",
        "completed_at",
        "recurrence_id",
        "category_id",
        "importance",
        "location",
        "timezone",
        "source",
        "created_at",
        "updated_at",
        "deleted_at",
    )

    /** 校验 NativeResult.data 是否是一个事件对象。 */
    fun validate(data: Any?) {
        if (data !is Map<*, *>) {
            throw NativeContractViolation("EventResponse data must be an object.", "data")
        }
        @Suppress("UNCHECKED_CAST")
        validateMap(data as Map<String, Any?>, "EventResponse")
    }

    /** 校验事件对象的每个字段类型和值域；列表响应会复用这个函数校验每一项。 */
    fun validateMap(map: Map<String, Any?>, parent: String) {
        ContractValidators.rejectUnknownFields(map, AllowedFields, parent)
        ContractValidators.requireString(map, "id", parent, nonEmpty = true)
        ContractValidators.requireString(map, "title", parent, nonEmpty = true)
        ContractValidators.optionalString(map, "content", parent)
        ContractValidators.requireString(map, "start_at", parent, nonEmpty = true)
        ContractValidators.requireString(map, "end_at", parent, nonEmpty = true)
        ContractValidators.requireBoolean(map, "is_all_day", parent)
        ContractValidators.requireBoolean(map, "has_recurrence", parent)
        ContractValidators.requireEnum(map, "status", parent, ContractEnums.EventStatus)
        ContractValidators.optionalString(map, "completed_at", parent)
        ContractValidators.optionalString(map, "recurrence_id", parent)
        ContractValidators.optionalString(map, "category_id", parent)
        ContractValidators.optionalEnum(map, "importance", parent, ContractEnums.Importance)
        ContractValidators.optionalString(map, "location", parent)
        ContractValidators.optionalString(map, "timezone", parent)
        ContractValidators.requireEnum(map, "source", parent, ContractEnums.CreateEventSource)
        ContractValidators.requireString(map, "created_at", parent, nonEmpty = true)
        ContractValidators.requireString(map, "updated_at", parent, nonEmpty = true)
        ContractValidators.optionalString(map, "deleted_at", parent)
    }
}
