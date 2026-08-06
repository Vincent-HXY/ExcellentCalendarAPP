package com.excellentcalendar.excellent_calendar.bridge.reminder

import com.excellentcalendar.excellent_calendar.android.notification.NotificationDisplayService
import com.excellentcalendar.excellent_calendar.android.notification.NotificationEventHub
import com.excellentcalendar.excellent_calendar.android.notification.NotificationPostResult
import com.excellentcalendar.excellent_calendar.android.notification.PreparedNotificationContent
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeContractViolation
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.V2FinalizeDelivery
import com.excellentcalendar.excellent_calendar.bridge.contract.V2PreparedDelivery
import com.excellentcalendar.excellent_calendar.bridge.native.NativeReminderBridge

interface V2ReminderDeliverer {
    fun deliverReminder(reminderId: String, expectedRemindAt: String, recoveryBatchId: String? = null): NativeResultContract
    fun deliverSummary(recoveryBatchId: String): NativeResultContract
}

class V2ReminderDeliveryService(
    private val nativeBridge: NativeReminderBridge,
    private val notifications: NotificationDisplayService,
    private val eventHub: NotificationEventHub,
    private val logger: ReminderOrchestrationLogger,
) : V2ReminderDeliverer {
    override fun deliverReminder(reminderId: String, expectedRemindAt: String, recoveryBatchId: String?): NativeResultContract =
        deliver(
            linkedMapOf(
                "kind" to "reminder",
                "reminder_id" to reminderId,
                "recovery_batch_id" to recoveryBatchId,
                "method" to "popup",
                "expected_remind_at" to expectedRemindAt,
            ),
            reminderId,
        )

    override fun deliverSummary(recoveryBatchId: String): NativeResultContract = deliver(
        linkedMapOf(
            "kind" to "recovery_summary",
            "reminder_id" to null,
            "recovery_batch_id" to recoveryBatchId,
            "method" to "popup",
            "expected_remind_at" to null,
        ),
        null,
    )

    private fun deliver(request: Map<String, Any?>, reminderId: String?): NativeResultContract {
        val preparedResult = parse(nativeBridge.prepareReminderDelivery(NativeContractJsonCodec.encodeObject(request))) {
            V2PreparedDelivery.fromData(it)
        }
        if (!preparedResult.ok) {
            val field = preparedResult.error?.details?.get("field") as? String
            logger.log(
                "reminder.prepare_delivery",
                reminderId,
                "failed code=${preparedResult.error?.code ?: "UNKNOWN"} " +
                    "retryable=${preparedResult.error?.retryable == true} field=${field ?: "none"}",
            )
            return preparedResult
        }
        val prepared = V2PreparedDelivery.fromData(preparedResult.data)
        val posted = notifications.postPrepared(
            PreparedNotificationContent(
                deliveryId = prepared.deliveryId,
                title = prepared.title,
                body = prepared.body,
                tapPayload = prepared.tapPayload,
            ),
        )
        return when (posted) {
            is NotificationPostResult.Success -> finalize(prepared, sent = true, failure = null, reminderId = reminderId)
            is NotificationPostResult.Failure -> finalize(prepared, sent = false, failure = posted, reminderId = reminderId)
        }
    }

    private fun finalize(
        prepared: V2PreparedDelivery,
        sent: Boolean,
        failure: NotificationPostResult.Failure?,
        reminderId: String?,
    ): NativeResultContract {
        val request = linkedMapOf<String, Any?>(
            "delivery_attempt_id" to prepared.attemptId,
            "outcome" to if (sent) "sent" else "failed",
            "failure_class" to failure?.let { if (it.retryable) "retryable" else "permanent" },
            "error_code" to failure?.code,
        )
        val finalizedResult = parse(nativeBridge.finalizeReminderDelivery(NativeContractJsonCodec.encodeObject(request))) {
            V2FinalizeDelivery.fromData(it)
        }
        if (!finalizedResult.ok) {
            logger.log(
                "reminder.finalize_delivery",
                reminderId,
                "failed code=${finalizedResult.error?.code ?: "UNKNOWN"} retryable=${finalizedResult.error?.retryable == true}",
            )
            return finalizedResult
        }
        val finalized = V2FinalizeDelivery.fromData(finalizedResult.data)
        if (sent) {
            if (!finalized.idempotentReplay) eventHub.emitDelivered(finalized.notification)
            logger.log("reminder.finalize_delivery", reminderId, "delivery_id=${prepared.deliveryId} outcome=sent replay=${finalized.idempotentReplay}")
            return NativeResultContract.success(
                linkedMapOf(
                    "delivery_id" to prepared.deliveryId,
                    "recovery_completed" to finalized.recoveryCompleted,
                    "idempotent_replay" to finalized.idempotentReplay,
                ),
                contractVersion = 2,
            )
        }
        logger.log("reminder.finalize_delivery", reminderId, "delivery_id=${prepared.deliveryId} outcome=failed code=${failure?.code}")
        return NativeResultContract.failure(
            code = failure?.code ?: NativeErrorCodes.NotificationDeliveryFailed,
            message = failure?.message ?: "Android notification delivery failed.",
            retryable = failure?.retryable ?: true,
            contractVersion = 2,
        )
    }

    private fun parse(json: String, validator: (Any?) -> Unit): NativeResultContract = try {
        NativeResultContract.fromJson(json, 2, validator)
    } catch (error: NativeContractViolation) {
        NativeResultContract.failure(
            code = NativeErrorCodes.ContractValidationFailed,
            message = error.message ?: "Reminder delivery response is malformed.",
            details = linkedMapOf("field" to error.field),
            contractVersion = 2,
        )
    }
}
