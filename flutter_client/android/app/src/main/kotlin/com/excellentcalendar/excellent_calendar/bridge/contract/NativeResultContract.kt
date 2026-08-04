package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import java.util.UUID

/**
 * native 层统一返回格式。
 *
 * 所有 C++ 调用都返回同一种外壳：
 * - `ok=true`：`data` 有值，`error` 必须为 null。
 * - `ok=false`：`data` 必须为 null，`error` 描述失败原因。
 *
 * 这种 Result 外壳能让 Dart 侧不必分别处理“抛异常、返回 null、返回错误码”等多种失败方式。
 */
data class NativeResultContract(
    /** 是否成功。 */
    val ok: Boolean,
    /** 成功时的业务数据；失败时必须为 null。 */
    val data: Any?,
    /** 失败时的错误对象；成功时必须为 null。 */
    val error: NativeErrorContract?,
    /** 合约版本，方便以后升级 JSON 协议时做兼容判断。 */
    val contractVersion: Int?,
    /** 单次请求 id，便于日志串联 Dart/Kotlin/C++ 的一次调用。 */
    val requestId: String?,
) {
    /** 转成 MethodChannel 可以直接返回给 Dart 的 Map。 */
    fun toMap(): Map<String, Any?> = linkedMapOf(
        "ok" to ok,
        "data" to data,
        "error" to error?.toMap(),
        "contract_version" to contractVersion,
        "request_id" to requestId,
    )

    companion object {
        /** 当前 Kotlin 层支持的 native 合约版本。 */
        const val ContractVersion = 1

        /**
         * 从 C++ 返回的 JSON 字符串解析 NativeResult。
         *
         * `dataValidator` 由调用方传入，因为不同 native 方法的 data 结构不同：
         * 创建事件要校验 EventResponse，搜索事件要校验 EventListResponse。
         */
        fun fromJson(
            json: String,
            dataValidator: (Any?) -> Unit,
        ): NativeResultContract = fromJson(json, ContractVersion, dataValidator)

        fun fromJson(
            json: String,
            expectedContractVersion: Int,
            dataValidator: (Any?) -> Unit,
        ): NativeResultContract {
            val map = try {
                NativeContractJsonCodec.decodeObject(json)
            } catch (error: Exception) {
                throw NativeContractViolation("NativeResult JSON is malformed.", cause = error)
            }
            return fromMap(map, expectedContractVersion, dataValidator)
        }

        /** 从 Map 构造并严格校验 NativeResult。 */
        fun fromMap(
            map: Map<String, Any?>,
            dataValidator: (Any?) -> Unit,
        ): NativeResultContract = fromMap(map, ContractVersion, dataValidator)

        fun fromMap(
            map: Map<String, Any?>,
            expectedContractVersion: Int,
            dataValidator: (Any?) -> Unit,
        ): NativeResultContract {
            if (expectedContractVersion >= 2) {
                ContractValidators.rejectUnknownFields(
                    map,
                    setOf("ok", "data", "error", "contract_version", "request_id"),
                    "NativeResult",
                )
            }
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
            if (contractVersion != null && contractVersion != expectedContractVersion) {
                throw NativeContractViolation("NativeResult.contract_version is unsupported.", "contract_version")
            }
            if (expectedContractVersion >= 2 && contractVersion == null) {
                throw NativeContractViolation("NativeResult.contract_version is required.", "contract_version")
            }
            if (requestId != null && requestId !is String) {
                throw NativeContractViolation("NativeResult.request_id must be string or null.", "request_id")
            }

            // ok=true 与 ok=false 的字段约束不同，所以分支校验能尽早发现 native 响应畸形。
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
                val error = NativeErrorContract.fromMap(rawError as Map<String, Any?>, strict = expectedContractVersion >= 2)
                NativeResultContract(
                    ok = false,
                    data = null,
                    error = error,
                    contractVersion = contractVersion as Int?,
                    requestId = requestId as String?,
                )
            }
        }

        /** 创建一个失败 NativeResult，供 Kotlin 层在捕获异常/校验失败时使用。 */
        fun failure(
            code: String,
            message: String,
            details: Map<String, Any?>? = null,
            retryable: Boolean = false,
            requestId: String? = null,
            contractVersion: Int = ContractVersion,
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
                contractVersion = contractVersion,
                requestId = requestId,
            )
        }

        /** Kotlin 本地能力成功时也使用统一 NativeResult 外壳。 */
        fun success(
            data: Any?,
            requestId: String = UUID.randomUUID().toString(),
            contractVersion: Int = ContractVersion,
        ): NativeResultContract {
            return NativeResultContract(
                ok = true,
                data = data,
                error = null,
                contractVersion = contractVersion,
                requestId = requestId,
            )
        }
    }
}
