package com.excellentcalendar.excellent_calendar.bridge.contract

/** Kotlin-owned wire mapping for delivery finalization and recovery planning requests. */
object ReminderDeliveryRequestContracts {
    fun finalizeDelivery(
        deliveryAttemptId: String,
        outcome: String,
        failureClass: String?,
        errorCode: String?,
        timezone: String,
    ): Map<String, Any?> {
        IanaTimezoneContract.require(timezone, "FinalizeDeliveryRequest.timezone")
        return linkedMapOf(
            "delivery_attempt_id" to deliveryAttemptId,
            "outcome" to outcome,
            "failure_class" to failureClass,
            "error_code" to errorCode,
            "timezone" to timezone,
        )
    }

    fun planRecovery(
        recoveryRequestId: String,
        triggerSource: String,
        timezone: String,
    ): Map<String, Any?> {
        IanaTimezoneContract.require(timezone, "PlanRecoveryRequest.timezone")
        return linkedMapOf(
            "recovery_request_id" to recoveryRequestId,
            "trigger_source" to triggerSource,
            "timezone" to timezone,
        )
    }

}

internal object IanaTimezoneContract {
    fun require(value: String, field: String): String {
        if (value.isBlank()) throw NativeContractViolation("$field must be non-empty.", field)
        val zone = try {
            java.time.ZoneId.of(value)
        } catch (error: java.time.DateTimeException) {
            throw NativeContractViolation("$field must be a valid IANA timezone.", field, error)
        }
        if (zone is java.time.ZoneOffset) {
            throw NativeContractViolation("$field must be an IANA timezone, not an offset.", field)
        }
        return value
    }
}
