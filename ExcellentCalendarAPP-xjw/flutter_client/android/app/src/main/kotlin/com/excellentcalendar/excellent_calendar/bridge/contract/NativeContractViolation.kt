package com.excellentcalendar.excellent_calendar.bridge.contract

/**
 * 合约校验失败异常。
 *
 * 这不是“程序崩溃”的异常，而是控制流的一部分：
 * 请求或响应不符合约定时抛出它，上层 `NativeMethodChannelHandler` 会捕获，
 * 再转换成 `CONTRACT_VALIDATION_FAILED` 的 NativeResult 返回给 Dart。
 *
 * `field` 用来指出具体哪个字段错了，例如 `CreateEventRequest.title`。
 */
class NativeContractViolation(
    message: String,
    val field: String? = null,
    cause: Throwable? = null,
) : Exception(message, cause)
