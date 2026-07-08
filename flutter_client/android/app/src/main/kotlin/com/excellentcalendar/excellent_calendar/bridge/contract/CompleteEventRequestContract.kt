package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec

/** 完成单次、非重复事件的请求合约。 */
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

        /** 校验必填 id、完成时间、来源，以及可选 note。 */
        private fun validate(map: Map<String, Any?>) {
            val parent = "CompleteEventRequest"
            ContractValidators.rejectUnknownFields(map, AllowedFields, parent)
            ContractValidators.requireString(map, "event_id", parent, nonEmpty = true)
            ContractValidators.requireString(map, "completed_at", parent, nonEmpty = true)
            ContractValidators.requireEnum(map, "source", parent, ContractEnums.CompleteEventSource)
            ContractValidators.optionalString(map, "note", parent)
        }
    }
}
