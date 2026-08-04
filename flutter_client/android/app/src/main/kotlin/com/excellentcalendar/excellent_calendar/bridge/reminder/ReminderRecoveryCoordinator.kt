package com.excellentcalendar.excellent_calendar.bridge.reminder

import android.content.Context
import com.excellentcalendar.excellent_calendar.android.notification.NotificationDisplayService
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeContractViolation
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderScheduleTrigger
import com.excellentcalendar.excellent_calendar.bridge.contract.V2RecoveryPlan
import com.excellentcalendar.excellent_calendar.bridge.native.NativeReminderBridge
import java.util.UUID

data class PendingRecoveryRequest(val requestId: String, val triggerSource: String)

interface RecoveryRequestStore {
    fun getOrCreate(triggerSource: String): PendingRecoveryRequest
    fun clearCompleted(requestId: String)
}

class SharedPreferencesRecoveryRequestStore(context: Context) : RecoveryRequestStore {
    private val preferences = context.applicationContext.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)

    @Synchronized
    override fun getOrCreate(triggerSource: String): PendingRecoveryRequest {
        val existingId = preferences.getString(KeyRequestId, null)
        val existingSource = preferences.getString(KeyTriggerSource, null)
        if (!existingId.isNullOrBlank() && !existingSource.isNullOrBlank()) {
            return PendingRecoveryRequest(existingId, existingSource)
        }
        val created = PendingRecoveryRequest(UUID.randomUUID().toString(), triggerSource)
        if (!preferences.edit().putString(KeyRequestId, created.requestId).putString(KeyTriggerSource, created.triggerSource).commit()) {
            throw IllegalStateException("Cannot persist reminder recovery request identity.")
        }
        return created
    }

    @Synchronized
    override fun clearCompleted(requestId: String) {
        if (preferences.getString(KeyRequestId, null) == requestId) {
            preferences.edit().remove(KeyRequestId).remove(KeyTriggerSource).apply()
        }
    }

    companion object {
        private const val PreferencesName = "reminder_recovery_v2"
        private const val KeyRequestId = "request_id"
        private const val KeyTriggerSource = "trigger_source"
    }
}

interface ReminderRecoveryRunner {
    fun recover(trigger: ReminderScheduleTrigger, canContinue: () -> Boolean): NativeResultContract
    fun recover(trigger: ReminderScheduleTrigger): NativeResultContract = recover(trigger) { true }
}

class ReminderRecoveryCoordinator(
    private val nativeBridge: NativeReminderBridge,
    private val deliveryService: V2ReminderDeliverer,
    private val notifications: NotificationDisplayService,
    private val requestStore: RecoveryRequestStore,
    private val logger: ReminderOrchestrationLogger,
) : ReminderRecoveryRunner {
    override fun recover(trigger: ReminderScheduleTrigger, canContinue: () -> Boolean): NativeResultContract {
        val triggerSource = trigger.toRecoveryTrigger() ?: return NativeResultContract.success(
            linkedMapOf("recovery_performed" to false),
            contractVersion = 2,
        )
        val pending = requestStore.getOrCreate(triggerSource)
        if (!canContinue()) return continuationRequired()
        val plannedResult = plan(pending)
        if (!plannedResult.ok) return plannedResult
        val planned = V2RecoveryPlan.fromData(plannedResult.data)
        if (planned.status == "completed") {
            requestStore.clearCompleted(pending.requestId)
            return recoverySuccess(planned)
        }

        planned.resolutions
            .filter { it.resolution.startsWith("abandoned_") }
            .forEach {
                if (!canContinue()) return continuationRequired()
                notifications.cancelDelivery(it.deliveryId)
            }

        if (planned.needsSummary) {
            if (!canContinue()) return continuationRequired()
            val summary = deliveryService.deliverSummary(planned.batchId)
            if (!summary.completesRecoveryDelivery()) return summary
        }
        for (reminder in planned.detailReminders) {
            if (reminder.isTerminal) continue
            if (!canContinue()) return continuationRequired()
            val detail = deliveryService.deliverReminder(reminder.reminderId, reminder.remindAt, planned.batchId)
            if (!detail.completesRecoveryDelivery()) return detail
        }

        if (!canContinue()) return continuationRequired()
        val completedResult = plan(pending)
        if (!completedResult.ok) return completedResult
        val completed = V2RecoveryPlan.fromData(completedResult.data)
        if (completed.status == "completed") requestStore.clearCompleted(pending.requestId)
        logger.log(
            "reminder.plan_recovery",
            null,
            "request_id=${pending.requestId} batch_id=${completed.batchId} status=${completed.status} details=${completed.detailReminders.size}",
        )
        return recoverySuccess(completed)
    }

    private fun plan(pending: PendingRecoveryRequest): NativeResultContract = try {
        NativeResultContract.fromJson(
            nativeBridge.planReminderRecovery(
                NativeContractJsonCodec.encodeObject(
                    linkedMapOf(
                        "recovery_request_id" to pending.requestId,
                        "trigger_source" to pending.triggerSource,
                    ),
                ),
            ),
            2,
        ) { V2RecoveryPlan.fromData(it) }
    } catch (error: NativeContractViolation) {
        NativeResultContract.failure(
            NativeErrorCodes.ContractValidationFailed,
            error.message ?: "Reminder recovery response is malformed.",
            details = linkedMapOf("field" to error.field),
            contractVersion = 2,
        )
    }

    private fun recoverySuccess(plan: V2RecoveryPlan): NativeResultContract = NativeResultContract.success(
        linkedMapOf(
            "recovery_performed" to true,
            "recovery_batch_id" to plan.batchId,
            "status" to plan.status,
            "detail_count" to plan.detailReminders.size,
            "continuation_required" to false,
        ),
        contractVersion = 2,
    )

    private fun continuationRequired(): NativeResultContract = NativeResultContract.success(
        linkedMapOf(
            "recovery_performed" to true,
            "continuation_required" to true,
        ),
        contractVersion = 2,
    )
}

private fun NativeResultContract.completesRecoveryDelivery(): Boolean =
    ok || error?.code == NativeErrorCodes.ReminderAlreadyConsumed

private fun ReminderScheduleTrigger.toRecoveryTrigger(): String? = when (this) {
    ReminderScheduleTrigger.AppStart -> "app_start"
    ReminderScheduleTrigger.BootCompleted -> "device_boot"
    ReminderScheduleTrigger.Mutation -> null
    ReminderScheduleTrigger.AppResume,
    ReminderScheduleTrigger.PackageReplaced,
    ReminderScheduleTrigger.TimeChanged,
    ReminderScheduleTrigger.TimezoneChanged,
    ReminderScheduleTrigger.PeriodicWorker,
    ReminderScheduleTrigger.AlarmFired,
    ReminderScheduleTrigger.ManualRetry,
    -> "alarm_reconcile"
}
