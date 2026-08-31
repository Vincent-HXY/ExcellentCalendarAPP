package com.excellentcalendar.excellent_calendar.bridge.channel

import com.excellentcalendar.excellent_calendar.bridge.contract.HabitContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReconcileReminderScheduleContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderScheduleTrigger
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderScheduleMode
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderScheduleReconciler

/** Preserves the C++ commit while adapting the recoverable Android scheduling side effect. */
internal class HabitMutationOrchestrator(
    private val coordinator: ReminderScheduleReconciler?,
    private val capabilityProvider: AnniversaryCapabilityProvider,
    private val retryEnqueuer: (() -> Unit)?,
    private val logger: NativeBridgeLogger,
) {
    enum class Shape { Mutation, Delete, CheckIn }

    fun mutate(method: String, nativeJson: String, shape: Shape): NativeResultContract {
        val validator: (Any?) -> Unit = when (shape) {
            Shape.Mutation -> HabitContracts::mutationCommit
            Shape.Delete -> HabitContracts::deleteCommit
            Shape.CheckIn -> HabitContracts::checkInCommit
        }
        val committed = NativeResultContract.fromJson(nativeJson, 2, validator)
        if (!committed.ok) return committed
        @Suppress("UNCHECKED_CAST")
        val commit = committed.data as Map<String, Any?>
        val required = commit["schedule_reconciliation_required"] as Boolean
        val needsNotification = when (shape) {
            Shape.Delete -> false
            Shape.Mutation -> reminderNeedsDelivery((commit["detail"] as Map<*, *>)["reminder_settings"])
            Shape.CheckIn -> reminderNeedsDelivery(commit["reminder_settings"])
        }
        val capability = capabilityAfterCommit(method, required, needsNotification)
        val publicData = projectPostScheduleState(
            commit,
            shape,
            capability["schedule_reconciliation_required"] as Boolean,
        ).apply {
            remove("schedule_reconciliation_required")
            this["capability"] = capability
        }
        return committed.copy(data = publicData)
    }

    private fun projectPostScheduleState(
        commit: Map<String, Any?>,
        shape: Shape,
        reconciliationRequired: Boolean,
    ): LinkedHashMap<String, Any?> = LinkedHashMap(commit).apply {
        when (shape) {
            Shape.Mutation -> {
                val detail = copyObject(commit["detail"])
                detail["reminder_settings"] = copyObject(detail["reminder_settings"]).apply {
                    this["schedule_reconciliation_required"] = reconciliationRequired
                }
                this["detail"] = detail
            }
            Shape.CheckIn -> {
                this["reminder_settings"] = copyObject(commit["reminder_settings"]).apply {
                    this["schedule_reconciliation_required"] = reconciliationRequired
                }
            }
            Shape.Delete -> Unit
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun copyObject(value: Any?): LinkedHashMap<String, Any?> =
        LinkedHashMap(value as Map<String, Any?>)

    private fun capabilityAfterCommit(method: String, required: Boolean, needsNotification: Boolean): Map<String, Any?> {
        var snapshot = capabilityProvider.snapshot()
        if (!required) return capability(snapshot, "not_required", false, emptyList())
        if (needsNotification && !snapshot.canPostNotifications) {
            enqueueRetry(method, "notification permission unavailable")
            return capability(snapshot, "pending_permission", true, listOf("notification_permission_unavailable"))
        }
        val reconciler = coordinator ?: run {
            enqueueRetry(method, "schedule coordinator unavailable")
            return capability(snapshot, "pending_reconciliation", true, listOf("scheduler_retry_required"))
        }
        val outcome = try {
            reconciler.reconcileWithOutcome(ReconcileReminderScheduleContract(ReminderScheduleTrigger.Mutation, force = true))
        } catch (error: Throwable) {
            logger.log(method, null, "Habit data committed; reconcile failed type=${error.javaClass.simpleName}")
            enqueueRetry(method, "schedule coordinator threw")
            return capability(snapshot, "pending_reconciliation", true, listOf("scheduler_retry_required"))
        }
        if (!outcome.result.ok) {
            enqueueRetry(method, "schedule coordinator returned ${outcome.result.error?.code ?: "UNKNOWN"}")
            return capability(snapshot, "pending_reconciliation", true, listOf("scheduler_retry_required"))
        }
        val action = (outcome.result.data as? Map<*, *>)?.get("action")
        snapshot = capabilityProvider.snapshot()
        if (action == "cancelled") return capability(snapshot, "not_required", false, emptyList())
        return when (outcome.scheduleMode) {
            ReminderScheduleMode.Exact -> capability(snapshot, "scheduled_exact", false, emptyList())
            ReminderScheduleMode.Approximate -> capability(snapshot, "scheduled_approximate", false, listOf("exact_alarm_permission_unavailable"))
            null -> {
                enqueueRetry(method, "no schedule mode")
                capability(snapshot, "pending_reconciliation", true, listOf("scheduler_retry_required"))
            }
        }
    }

    private fun reminderNeedsDelivery(value: Any?): Boolean {
        val settings = value as? Map<*, *> ?: return false
        return settings["is_enabled"] == true && (settings["active_reminder_count"] as? Number)?.toInt()?.let { it > 0 } == true
    }

    private fun capability(
        snapshot: AnniversaryCapabilitySnapshot,
        status: String,
        required: Boolean,
        reasons: List<String>,
    ): Map<String, Any?> = linkedMapOf(
        "schedule_status" to status,
        "schedule_reconciliation_required" to required,
        "notification_permission_status" to snapshot.notificationPermissionStatus,
        "exact_alarm_permission_status" to snapshot.exactAlarmPermissionStatus,
        "degradation_reasons" to reasons.distinct(),
    )

    private fun enqueueRetry(method: String, reason: String) {
        logger.log(method, null, "Habit data committed; reconcile deferred reason=$reason")
        runCatching { retryEnqueuer?.invoke() }
    }
}
