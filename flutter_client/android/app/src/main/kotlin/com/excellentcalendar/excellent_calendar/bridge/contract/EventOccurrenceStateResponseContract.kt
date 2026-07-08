package com.excellentcalendar.excellent_calendar.bridge.contract

/**
 * 事件 occurrence 状态响应合约。
 *
 * 对重复事件来说，一个 event 可以有很多 occurrence。这个响应描述某一次 occurrence
 * 的完成/跳过/取消等状态。
 */
object EventOccurrenceStateResponseContract {
    /** 状态响应允许的字段集合。 */
    private val AllowedFields = setOf(
        "id",
        "event_id",
        "occurrence_start_at",
        "status",
        "completed_at",
        "note",
        "source",
        "created_at",
        "updated_at",
        "deleted_at",
    )

    /** 校验 NativeResult.data 是否是 occurrence 状态对象。 */
    fun validate(data: Any?) {
        if (data !is Map<*, *>) {
            throw NativeContractViolation("EventOccurrenceStateResponse data must be an object.", "data")
        }
        @Suppress("UNCHECKED_CAST")
        validateMap(data as Map<String, Any?>, "EventOccurrenceStateResponse")
    }

    /** 校验 occurrence 状态对象的字段。 */
    fun validateMap(map: Map<String, Any?>, parent: String) {
        ContractValidators.rejectUnknownFields(map, AllowedFields, parent)
        ContractValidators.requireString(map, "id", parent, nonEmpty = true)
        ContractValidators.requireString(map, "event_id", parent, nonEmpty = true)
        ContractValidators.requireString(map, "occurrence_start_at", parent, nonEmpty = true)
        ContractValidators.requireEnum(map, "status", parent, ContractEnums.EventOccurrenceStatus)
        ContractValidators.optionalString(map, "completed_at", parent)
        ContractValidators.optionalString(map, "note", parent)
        ContractValidators.requireEnum(map, "source", parent, ContractEnums.ReminderSource)
        ContractValidators.requireString(map, "created_at", parent, nonEmpty = true)
        ContractValidators.requireString(map, "updated_at", parent, nonEmpty = true)
        ContractValidators.optionalString(map, "deleted_at", parent)
    }
}
