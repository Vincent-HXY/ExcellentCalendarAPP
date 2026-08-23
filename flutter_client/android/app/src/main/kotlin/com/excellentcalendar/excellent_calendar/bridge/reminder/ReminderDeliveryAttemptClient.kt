package com.excellentcalendar.excellent_calendar.bridge.reminder

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeContractViolation
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.V2FinalizeDelivery
import com.excellentcalendar.excellent_calendar.bridge.contract.V2PreparedDelivery
import com.excellentcalendar.excellent_calendar.bridge.native.NativeReminderBridge

class ReminderDeliveryAttemptClient(
    private val nativeBridge: NativeReminderBridge,
    private val logger: ReminderOrchestrationLogger,
) {
    fun prepare(request: Map<String, Any?>, reminderId: String?): NativeResultContract {
        val result = parse(nativeBridge.prepareReminderDelivery(NativeContractJsonCodec.encodeObject(request))) {
            V2PreparedDelivery.fromData(it)
        }
        if (!result.ok) {
            logger.log(
                "reminder.prepare_delivery",
                reminderId,
                "failed code=${result.error?.code ?: "UNKNOWN"} retryable=${result.error?.retryable == true}",
            )
        }
        return result
    }

    fun finalize(
        prepared: V2PreparedDelivery,
        outcome: String,
        failureCode: String? = null,
        failureRetryable: Boolean = false,
        reminderId: String? = prepared.notification["reminder_id"] as? String,
    ): NativeResultContract {
        val request = linkedMapOf<String, Any?>(
            "delivery_attempt_id" to prepared.attemptId,
            "outcome" to outcome,
            "failure_class" to if (outcome == "failed") if (failureRetryable) "retryable" else "permanent" else null,
            "error_code" to if (outcome == "failed") failureCode else null,
        )
        val result = parse(nativeBridge.finalizeReminderDelivery(NativeContractJsonCodec.encodeObject(request))) {
            V2FinalizeDelivery.fromData(it)
        }
        logger.log(
            "reminder.finalize_delivery",
            reminderId,
            "delivery_id=${prepared.deliveryId} outcome=$outcome ok=${result.ok} code=${result.error?.code ?: "none"}",
        )
        return result
    }

    private fun parse(json: String, validator: (Any?) -> Unit): NativeResultContract = try {
        NativeResultContract.fromJson(json, 2, validator)
    } catch (error: NativeContractViolation) {
        NativeResultContract.failure(
            NativeErrorCodes.ContractValidationFailed,
            error.message ?: "Reminder delivery response is malformed.",
            details = linkedMapOf("field" to error.field),
            contractVersion = 2,
        )
    }
}
