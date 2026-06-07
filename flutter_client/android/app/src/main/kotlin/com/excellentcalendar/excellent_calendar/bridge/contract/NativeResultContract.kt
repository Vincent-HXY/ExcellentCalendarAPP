package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec

data class NativeResultContract(
    val ok: Boolean,
    val data: Any?,
    val error: NativeErrorContract?,
    val contractVersion: Int?,
    val requestId: String?,
) {
    fun toMap(): Map<String, Any?> = linkedMapOf(
        "ok" to ok,
        "data" to data,
        "error" to error?.toMap(),
        "contract_version" to contractVersion,
        "request_id" to requestId,
    )

    companion object {
        const val ContractVersion = 1

        fun fromJson(
            json: String,
            dataValidator: (Any?) -> Unit,
        ): NativeResultContract {
            val map = try {
                NativeContractJsonCodec.decodeObject(json)
            } catch (error: Exception) {
                throw NativeContractViolation("NativeResult JSON is malformed.", cause = error)
            }
            return fromMap(map, dataValidator)
        }

        fun fromMap(
            map: Map<String, Any?>,
            dataValidator: (Any?) -> Unit,
        ): NativeResultContract {
            if (!map.containsKey("ok") || !map.containsKey("data") || !map.containsKey("error")) {
                throw NativeContractViolation("NativeResult must contain ok, data, and error.")
            }

            val ok = map["ok"]
            val data = map["data"]
            val rawError = map["error"]
            val contractVersion = map["contract_version"]
            val requestId = map["request_id"]

            if (ok !is Boolean) {
                throw NativeContractViolation("NativeResult.ok must be boolean.", "ok")
            }
            if (contractVersion != null && contractVersion !is Int) {
                throw NativeContractViolation("NativeResult.contract_version must be integer or null.", "contract_version")
            }
            if (contractVersion != null && contractVersion != ContractVersion) {
                throw NativeContractViolation("NativeResult.contract_version is unsupported.", "contract_version")
            }
            if (requestId != null && requestId !is String) {
                throw NativeContractViolation("NativeResult.request_id must be string or null.", "request_id")
            }

            return if (ok) {
                if (rawError != null) {
                    throw NativeContractViolation("NativeResult.error must be null when ok=true.", "error")
                }
                dataValidator(data)
                NativeResultContract(
                    ok = true,
                    data = data,
                    error = null,
                    contractVersion = contractVersion as Int?,
                    requestId = requestId as String?,
                )
            } else {
                if (data != null) {
                    throw NativeContractViolation("NativeResult.data must be null when ok=false.", "data")
                }
                if (rawError !is Map<*, *>) {
                    throw NativeContractViolation("NativeResult.error must be object when ok=false.", "error")
                }
                @Suppress("UNCHECKED_CAST")
                val error = NativeErrorContract.fromMap(rawError as Map<String, Any?>)
                NativeResultContract(
                    ok = false,
                    data = null,
                    error = error,
                    contractVersion = contractVersion as Int?,
                    requestId = requestId as String?,
                )
            }
        }

        fun failure(
            code: String,
            message: String,
            details: Map<String, Any?>? = null,
            retryable: Boolean = false,
            requestId: String? = null,
        ): NativeResultContract {
            return NativeResultContract(
                ok = false,
                data = null,
                error = NativeErrorContract(
                    code = code,
                    message = message,
                    details = details,
                    retryable = retryable,
                ),
                contractVersion = ContractVersion,
                requestId = requestId,
            )
        }
    }
}
