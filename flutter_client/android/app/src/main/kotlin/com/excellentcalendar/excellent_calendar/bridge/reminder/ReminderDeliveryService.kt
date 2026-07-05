package com.excellentcalendar.excellent_calendar.bridge.reminder

import com.excellentcalendar.excellent_calendar.android.notification.NotificationDisplayService
import com.excellentcalendar.excellent_calendar.android.notification.NotificationEventHub
import com.excellentcalendar.excellent_calendar.android.notification.NotificationPostResult
import com.excellentcalendar.excellent_calendar.android.notification.ReminderNotificationContent
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.ConsumeReminderAfterDeliveryResponseContract
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.NotificationResponseContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderResponseContract
import com.excellentcalendar.excellent_calendar.bridge.native.NativeEventBridge
import java.time.Instant

sealed class ReminderDeliveryResult {
    data class Delivered(val notification: Map<String, Any?>) : ReminderDeliveryResult()
    data class Skipped(val reason: String) : ReminderDeliveryResult()
    data class Failed(val code: String, val message: String) : ReminderDeliveryResult()
}

class ReminderDeliveryService(
    private val nativeBridge: NativeEventBridge,
    private val notifications: NotificationDisplayService,
    private val eventHub: NotificationEventHub,
    private val logger: ReminderOrchestrationLogger,
    private val nowUtc: () -> String = { Instant.now().toString() },
) {
    fun deliver(reminderId: String, plannedAt: String?): ReminderDeliveryResult {
        val loaded = NativeResultContract.fromJson(
            nativeBridge.getReminder(
                NativeContractJsonCodec.encodeObject(linkedMapOf("id" to reminderId)),
            ),
            ReminderResponseContract::validate,
        )
        if (!loaded.ok) {
            return ReminderDeliveryResult.Failed(
                loaded.error?.code ?: "NATIVE_INTERNAL_ERROR",
                loaded.error?.message ?: "Reminder lookup failed.",
            )
        }
        val reminder = ReminderContract.fromData(loaded.data)
        if (!reminder.isEnabled || reminder.deletedAt != null || reminder.status !in DeliverableStatuses) {
            return ReminderDeliveryResult.Skipped("Reminder is not deliverable in status=${reminder.status}.")
        }
        if ("popup" !in reminder.methods) {
            markFailed(reminder.id, "Reminder has no Android V1 popup delivery method.")
            return ReminderDeliveryResult.Skipped("Reminder method is unsupported by Android V1.")
        }

        val sentAt = nowUtc()
        val content = ReminderNotificationContent(
            reminderId = reminder.id,
            targetType = reminder.targetType,
            targetId = reminder.targetId,
            title = DefaultTitle,
            body = reminder.message,
            plannedAt = plannedAt ?: reminder.remindAt,
        )
        return when (val posted = notifications.post(content, sentAt)) {
            is NotificationPostResult.Failure -> {
                recordFailedNotification(content, posted.message)
                markFailed(reminder.id, posted.message)
                ReminderDeliveryResult.Failed(posted.code, posted.message)
            }
            is NotificationPostResult.Success -> consumeSuccessfulDelivery(content, sentAt)
        }
    }

    private fun consumeSuccessfulDelivery(
        content: ReminderNotificationContent,
        sentAt: String,
    ): ReminderDeliveryResult {
        val request = linkedMapOf<String, Any?>(
            "reminder_id" to content.reminderId,
            "method" to "popup",
            "title" to content.title,
            "body" to content.body,
            "planned_at" to content.plannedAt,
            "sent_at" to sentAt,
            "delete_after_sent" to true,
        )
        val consumed = NativeResultContract.fromJson(
            nativeBridge.consumeReminderAfterDelivery(NativeContractJsonCodec.encodeObject(request)),
        ) { ConsumeReminderAfterDeliveryResponseContract.notification(it) }
        if (!consumed.ok) {
            notifications.cancel(content.reminderId)
            logger.log("reminder.consume_after_delivery", content.reminderId, "consume failed; notification cancelled")
            return ReminderDeliveryResult.Failed(
                consumed.error?.code ?: "NATIVE_INTERNAL_ERROR",
                consumed.error?.message ?: "Reminder consumption failed.",
            )
        }
        val notification = ConsumeReminderAfterDeliveryResponseContract.notification(consumed.data)
        eventHub.emitDelivered(notification)
        return ReminderDeliveryResult.Delivered(notification)
    }

    private fun recordFailedNotification(
        content: ReminderNotificationContent,
        failureReason: String,
    ) {
        try {
            val request = linkedMapOf<String, Any?>(
                "reminder_id" to content.reminderId,
                "target_type" to content.targetType,
                "target_id" to content.targetId,
                "method" to "popup",
                "title" to content.title,
                "body" to content.body,
                "planned_at" to content.plannedAt,
                "sent_at" to null,
                "status" to "failed",
                "failure_reason" to failureReason,
            )
            NativeResultContract.fromJson(
                nativeBridge.createNotification(NativeContractJsonCodec.encodeObject(request)),
                NotificationResponseContract::validate,
            )
        } catch (error: Throwable) {
            logger.log("notification.create", content.reminderId, "failed log write type=${error.javaClass.simpleName}")
        }
    }

    private fun markFailed(reminderId: String, failureReason: String) {
        try {
            val request = NativeContractJsonCodec.encodeObject(
                linkedMapOf("id" to reminderId, "failure_reason" to failureReason),
            )
            NativeResultContract.fromJson(
                nativeBridge.markReminderFailed(request),
                ReminderResponseContract::validate,
            )
        } catch (error: Throwable) {
            logger.log("reminder.mark_failed", reminderId, "state write failed type=${error.javaClass.simpleName}")
        }
    }

    companion object {
        private const val DefaultTitle = "Calendar reminder"
        private val DeliverableStatuses = setOf("scheduled", "pending", "failed")
    }
}
