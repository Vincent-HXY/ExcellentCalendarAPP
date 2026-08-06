package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec

/** reminder.cancel 的请求合约。 */
data class CancelReminderRequestContract(
    private val payload: Map<String, Any?>,
) {
    val id: String
        get() = payload["id"] as String

    fun toJson(): String = NativeContractJsonCodec.encodeObject(payload)

    fun toMap(): Map<String, Any?> = payload

    companion object {
        private val AllowedFields = setOf("id", "reason")

        fun fromMethodArguments(arguments: Any?): CancelReminderRequestContract {
            val map = try {
                NativeContractJsonCodec.normalizeMap(arguments)
            } catch (error: IllegalArgumentException) {
                throw NativeContractViolation(error.message ?: "Invalid MethodChannel arguments.", cause = error)
            }
            validate(map)
            return CancelReminderRequestContract(map)
        }

        private fun validate(map: Map<String, Any?>) {
            val parent = "CancelReminderRequest"
            ContractValidators.rejectUnknownFields(map, AllowedFields, parent)
            ContractValidators.requireString(map, "id", parent, nonEmpty = true)
            ContractValidators.optionalString(map, "reason", parent)
        }
    }
}
