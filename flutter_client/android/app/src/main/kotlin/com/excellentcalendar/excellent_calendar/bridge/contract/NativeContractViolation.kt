package com.excellentcalendar.excellent_calendar.bridge.contract

class NativeContractViolation(
    message: String,
    val field: String? = null,
    cause: Throwable? = null,
) : Exception(message, cause)
