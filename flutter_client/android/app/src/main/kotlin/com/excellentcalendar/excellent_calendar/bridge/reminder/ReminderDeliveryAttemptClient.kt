package com.excellentcalendar.excellent_calendar.bridge.reminder

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeContractViolation
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderDeliveryRequestContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.V2FinalizeDelivery
import com.excellentcalendar.excellent_calendar.bridge.contract.V2PreparedDelivery
import com.excellentcalendar.excellent_calendar.bridge.native.NativeReminderBridge
import com.excellentcalendar.excellent_calendar.bridge.runtime.DeviceTimezoneProvider

class ReminderDeliveryAttemptClient(
    private val nativeBridge: NativeReminderBridge,
    private val logger: ReminderOrchestrationLogger,
    private val timezoneProvider: DeviceTimezoneProvider,
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
        val request = try {
            ReminderDeliveryRequestContracts.finalizeDelivery(
                deliveryAttemptId = prepared.attemptId,
                outcome = outcome,
                failureClass = if (outcome == "failed") {
                    if (failureRetryable) "retryable" else "permanent"
                } else {
                    null
                },
                errorCode = if (outcome == "failed") failureCode else null,
                timezone = timezoneProvider.currentTimezone(),
            )
        } catch (error: NativeContractViolation) {
            return contractFailure(error, "Reminder delivery request is malformed.")
        }
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

    private fun contractFailure(
        error: NativeContractViolation,
        fallbackMessage: String,
    ): NativeResultContract =
        NativeResultContract.failure(
            NativeErrorCodes.ContractValidationFailed,
            error.message ?: fallbackMessage,
            details = linkedMapOf("field" to error.field),
            contractVersion = 2,
        )

    private fun parse(json: String, validator: (Any?) -> Unit): NativeResultContract = try {
        NativeResultContract.fromJson(json, 2, validator)
    } catch (error: NativeContractViolation) {
        contractFailure(error, "Reminder delivery response is malformed.")
    }
}
