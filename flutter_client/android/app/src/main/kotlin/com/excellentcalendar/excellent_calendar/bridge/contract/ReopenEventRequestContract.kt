package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec

/**
 * 重新打开事件实例请求合约。
 *
 * 用于把已经完成/跳过/取消的事件 occurrence 恢复到可处理状态。
 */
data class ReopenEventRequestContract(
    private val payload: Map<String, Any?>,
) {
    /** 转成 JSON 后传给 C++。 */
    fun toJson(): String = NativeContractJsonCodec.encodeObject(payload)

    /** 返回 Map，便于测试。 */
    fun toMap(): Map<String, Any?> = payload

    companion object {
        /** 重新打开只需要事件 id，以及可选的 occurrence 起始时间。 */
        private val AllowedFields = setOf(
            "event_id",
            "occurrence_start_at",
        )

        /** 从 MethodChannel arguments 创建并校验请求。 */
        fun fromMethodArguments(arguments: Any?): ReopenEventRequestContract {
            val map = try {
                NativeContractJsonCodec.normalizeMap(arguments)
            } catch (error: IllegalArgumentException) {
                throw NativeContractViolation(error.message ?: "Invalid MethodChannel arguments.", cause = error)
            }
            validate(map)
            return ReopenEventRequestContract(map)
        }

        /** 校验 event_id 必填，occurrence_start_at 可选。 */
        private fun validate(map: Map<String, Any?>) {
            val parent = "ReopenEventRequest"
            ContractValidators.rejectUnknownFields(map, AllowedFields, parent)
            ContractValidators.requireString(map, "event_id", parent, nonEmpty = true)
            ContractValidators.optionalString(map, "occurrence_start_at", parent)
        }
    }
}
