package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec

/**
 * 完成事件实例请求合约。
 *
 * 事件可能是一次性事件，也可能是重复事件中的某一次。`occurrence_start_at` 用来定位
 * 重复事件的具体 occurrence；一次性事件可以不传。
 */
data class CompleteEventRequestContract(
    private val payload: Map<String, Any?>,
) {
    /** 转成 JSON 后传给 C++。 */
    fun toJson(): String = NativeContractJsonCodec.encodeObject(payload)

    /** 返回 Map，便于测试断言。 */
    fun toMap(): Map<String, Any?> = payload

    companion object {
        /** 允许的字段集合。 */
        private val AllowedFields = setOf(
            "event_id",
            "occurrence_start_at",
            "completed_at",
            "source",
            "note",
        )

        /** 从 Flutter MethodChannel arguments 创建合约对象。 */
        fun fromMethodArguments(arguments: Any?): CompleteEventRequestContract {
            val map = try {
                NativeContractJsonCodec.normalizeMap(arguments)
            } catch (error: IllegalArgumentException) {
                throw NativeContractViolation(error.message ?: "Invalid MethodChannel arguments.", cause = error)
            }
            validate(map)
            return CompleteEventRequestContract(map)
        }

        /** 校验必填 id、完成时间、来源，以及可选 occurrence/note。 */
        private fun validate(map: Map<String, Any?>) {
            val parent = "CompleteEventRequest"
            ContractValidators.rejectUnknownFields(map, AllowedFields, parent)
            ContractValidators.requireString(map, "event_id", parent, nonEmpty = true)
            ContractValidators.optionalString(map, "occurrence_start_at", parent)
            ContractValidators.requireString(map, "completed_at", parent, nonEmpty = true)
            ContractValidators.requireEnum(map, "source", parent, ContractEnums.ReminderSource)
            ContractValidators.optionalString(map, "note", parent)
        }
    }
}
