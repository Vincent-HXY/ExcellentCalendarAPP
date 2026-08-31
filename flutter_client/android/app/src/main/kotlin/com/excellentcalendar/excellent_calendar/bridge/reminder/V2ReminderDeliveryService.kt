package com.excellentcalendar.excellent_calendar.bridge.reminder

import com.excellentcalendar.excellent_calendar.android.notification.NotificationDisplayService
import com.excellentcalendar.excellent_calendar.android.notification.NotificationEventHub
import com.excellentcalendar.excellent_calendar.android.notification.NotificationPostResult
import com.excellentcalendar.excellent_calendar.android.notification.PreparedNotificationContent
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.V2FinalizeDelivery
import com.excellentcalendar.excellent_calendar.bridge.contract.V2PreparedDelivery
import com.excellentcalendar.excellent_calendar.bridge.native.NativeReminderBridge
import com.excellentcalendar.excellent_calendar.bridge.runtime.AndroidDeviceTimezoneProvider
import com.excellentcalendar.excellent_calendar.bridge.runtime.DeviceTimezoneProvider
import com.excellentcalendar.excellent_calendar.android.ring.RingRuntime

interface V2ReminderDeliverer {
    fun deliverReminder(reminderId: String, expectedRemindAt: String, recoveryBatchId: String? = null): NativeResultContract
    fun deliverReminder(reminderId: String, expectedRemindAt: String, recoveryBatchId: String?, method: String): NativeResultContract =
        deliverReminder(reminderId, expectedRemindAt, recoveryBatchId)
    fun deliverSummary(recoveryBatchId: String): NativeResultContract
    fun deliverAnniversaryCatchUp(recoveryBatchId: String, deliveryId: String): NativeResultContract =
        NativeResultContract.failure(
            NativeErrorCodes.FeatureNotImplemented,
            "Anniversary catch-up delivery is unavailable.",
            contractVersion = 2,
        )
}

class V2ReminderDeliveryService(
    private val nativeBridge: NativeReminderBridge,
    private val notifications: NotificationDisplayService,
    private val eventHub: NotificationEventHub,
    private val logger: ReminderOrchestrationLogger,
    private val ringRuntime: RingRuntime? = null,
    private val timezoneProvider: DeviceTimezoneProvider = AndroidDeviceTimezoneProvider,
    private val attemptClient: ReminderDeliveryAttemptClient =
        ReminderDeliveryAttemptClient(nativeBridge, logger, timezoneProvider),
) : V2ReminderDeliverer {
    override fun deliverReminder(reminderId: String, expectedRemindAt: String, recoveryBatchId: String?): NativeResultContract =
        deliverReminder(reminderId, expectedRemindAt, recoveryBatchId, "popup")

    override fun deliverReminder(
        reminderId: String,
        expectedRemindAt: String,
        recoveryBatchId: String?,
        method: String,
    ): NativeResultContract =
        deliver(
            linkedMapOf(
                "kind" to "reminder",
                "reminder_id" to reminderId,
                "recovery_batch_id" to recoveryBatchId,
                "delivery_id" to null,
                "method" to method,
                "expected_remind_at" to expectedRemindAt,
                "timezone" to timezoneProvider.currentTimezone(),
            ),
            reminderId,
        )

    override fun deliverSummary(recoveryBatchId: String): NativeResultContract = deliver(
        linkedMapOf(
            "kind" to "recovery_summary",
            "reminder_id" to null,
            "recovery_batch_id" to recoveryBatchId,
            "delivery_id" to null,
            "method" to "popup",
            "expected_remind_at" to null,
        ),
        null,
    )

    override fun deliverAnniversaryCatchUp(
        recoveryBatchId: String,
        deliveryId: String,
    ): NativeResultContract = deliver(
        linkedMapOf(
            "kind" to "anniversary_catch_up",
            "reminder_id" to null,
            "recovery_batch_id" to recoveryBatchId,
            "delivery_id" to deliveryId,
            "method" to "popup",
            "expected_remind_at" to null,
        ),
        null,
    )

    private fun deliver(request: Map<String, Any?>, reminderId: String?): NativeResultContract {
        val preparedResult = attemptClient.prepare(request, reminderId)
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
        if (prepared.method == "ring") {
            val runtime = ringRuntime ?: return NativeResultContract.failure(
                NativeErrorCodes.RingCapabilityUnavailable,
                "Android ring runtime is unavailable.",
                retryable = true,
                contractVersion = 2,
            )
            return runtime.enqueue(prepared)
        }
        val posted = notifications.postPrepared(
            PreparedNotificationContent(
                deliveryId = prepared.deliveryId,
                title = prepared.title,
                body = prepared.body,
                tapPayload = prepared.tapPayload,
                habitActionPayload = prepared.habitActionPayload,
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
        val finalizedResult = attemptClient.finalize(
            prepared,
            if (sent) "sent" else "failed",
            failure?.code,
            failure?.retryable ?: false,
            reminderId,
        )
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

}
