package com.excellentcalendar.excellent_calendar.bridge.contract

/**
 * 合约校验失败异常。
 *
 * 这不是“程序崩溃”的异常，而是控制流的一部分：
 * 请求或响应不符合约定时抛出它，上层 `NativeMethodChannelHandler` 会捕获，
 * 再转换成稳定错误码的 NativeResult 返回给 Dart。默认错误码仍是
 * `CONTRACT_VALIDATION_FAILED`；只有 Contract 明确声明更具体的边界错误时才覆盖。
 *
 * `field` 用来指出具体哪个字段错了，例如 `CreateEventRequest.title`。
 * `errorCode` 必须来自 `error_codes.yaml`，用于 Calendar token/cursor 等有独立语义的失败。
 */
class NativeContractViolation(
    message: String,
    val field: String? = null,
    cause: Throwable? = null,
    val errorCode: String = NativeErrorCodes.ContractValidationFailed,
) : Exception(message, cause)
