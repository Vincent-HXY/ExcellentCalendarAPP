package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec

/**
 * 重新打开单个已完成 Event 的请求合约。
 */
data class ReopenEventRequestContract(
    private val payload: Map<String, Any?>,
) {
    /** 转成 JSON 后传给 C++。 */
    fun toJson(): String = NativeContractJsonCodec.encodeObject(payload)

    /** 返回 Map，便于测试。 */
    fun toMap(): Map<String, Any?> = payload

    companion object {
        /** 重新打开只需要 Event id；不再接受 occurrence_start_at。 */
        private val AllowedFields = setOf(
            "event_id",
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

        /** 校验 event_id 必填，并拒绝旧版 occurrence_start_at。 */
        private fun validate(map: Map<String, Any?>) {
            val parent = "ReopenEventRequest"
            ContractValidators.rejectUnknownFields(map, AllowedFields, parent)
            ContractValidators.requireString(map, "event_id", parent, nonEmpty = true)
        }
    }
}
