package com.excellentcalendar.excellent_calendar.bridge.channel

import com.excellentcalendar.excellent_calendar.bridge.contract.AnniversaryResponseContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReconcileReminderScheduleContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderScheduleTrigger
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderScheduleReconciler
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderScheduleMode

data class AnniversaryCapabilitySnapshot(
    val notificationPermissionStatus: String,
    val exactAlarmPermissionStatus: String,
    val canPostNotifications: Boolean,
    val canScheduleExactAlarms: Boolean,
)

fun interface AnniversaryCapabilityProvider {
    fun snapshot(): AnniversaryCapabilitySnapshot
}

/** Combines an authoritative C++ logical commit with the recoverable Android scheduling side effect. */
internal class AnniversaryMethodOrchestrator(
    private val reminderScheduleCoordinator: ReminderScheduleReconciler?,
    private val capabilityProvider: AnniversaryCapabilityProvider,
    private val reconcileRetryEnqueuer: (() -> Unit)?,
    private val logger: NativeBridgeLogger,
) {
    fun mutate(
        method: String,
        nativeJson: String,
        nativeDataValidator: (Any?) -> Unit,
        delete: Boolean = false,
    ): NativeResultContract {
        val committed = NativeResultContract.fromJson(nativeJson, 2, nativeDataValidator)
        if (!committed.ok) return committed
        val committedData = objectMap(committed.data, "$method.data")
        val reconciliationRequired = if (delete) {
            committedData["schedule_reconciliation_required"] as Boolean
        } else {
            reminderSettings(committedData)["schedule_reconciliation_required"] as Boolean
        }
        val notificationDeliveryRequired = if (delete) {
            false
        } else {
            requiresNotificationDelivery(reminderSettings(committedData))
        }
        val capability = reconcileAfterCommit(
            method,
            reconciliationRequired,
            notificationDeliveryRequired,
        )
        val publicData = if (delete) {
            linkedMapOf<String, Any?>(
                "data_saved" to true,
                "commit" to committedData,
                "capability" to capability,
            ).also(AnniversaryResponseContracts::deleteOperation)
        } else {
            val detail = withReconciliationFlag(
                committedData,
                capability["schedule_reconciliation_required"] as Boolean,
            )
            linkedMapOf<String, Any?>(
                "data_saved" to true,
                "detail" to detail,
                "capability" to capability,
            ).also(AnniversaryResponseContracts::mutation)
        }
        return committed.copy(data = publicData)
    }

    fun detail(method: String, nativeJson: String): NativeResultContract {
        val nativeResult = NativeResultContract.fromJson(nativeJson, 2, AnniversaryResponseContracts::nativeDetail)
        if (!nativeResult.ok) return nativeResult
        val detail = objectMap(nativeResult.data, "$method.data")
        val settings = reminderSettings(detail)
        val required = settings["schedule_reconciliation_required"] as Boolean
        val capability = passiveCapability(required, requiresNotificationDelivery(settings))
        val publicData = linkedMapOf<String, Any?>(
            "detail" to withReconciliationFlag(detail, required),
            "capability" to capability,
        ).also(AnniversaryResponseContracts::detailView)
        return nativeResult.copy(data = publicData)
    }

    private fun reconcileAfterCommit(
        method: String,
        required: Boolean,
        notificationDeliveryRequired: Boolean,
    ): Map<String, Any?> {
        if (!required) return passiveCapability(false, notificationDeliveryRequired)
        val snapshot = capabilityProvider.snapshot()
        if (notificationDeliveryRequired && !snapshot.canPostNotifications) {
            enqueueRetry(method, "notification permission unavailable")
            return capability(
                snapshot = snapshot,
                scheduleStatus = "pending_permission",
                required = true,
                reasons = listOf("notification_permission_unavailable"),
            )
        }
        val coordinator = reminderScheduleCoordinator
        if (coordinator == null) {
            enqueueRetry(method, "schedule coordinator unavailable")
            return capability(
                snapshot = snapshot,
                scheduleStatus = "pending_reconciliation",
                required = true,
                reasons = listOf("scheduler_retry_required"),
            )
        }
        val reconciliation = try {
            coordinator.reconcileWithOutcome(
                ReconcileReminderScheduleContract(ReminderScheduleTrigger.Mutation, force = true),
            )
        } catch (error: Throwable) {
            logger.log(method, null, "anniversary committed; reconcile threw type=${error.javaClass.simpleName}")
            enqueueRetry(method, "schedule coordinator failed")
            return capability(
                snapshot = snapshot,
                scheduleStatus = "pending_reconciliation",
                required = true,
                reasons = listOf("scheduler_retry_required"),
            )
        }
        val reconciled = reconciliation.result
        if (!reconciled.ok) {
            enqueueRetry(method, "schedule coordinator returned ${reconciled.error?.code ?: "UNKNOWN"}")
            val exactUnavailable = !snapshot.canScheduleExactAlarms
            return capability(
                snapshot = snapshot,
                scheduleStatus = if (exactUnavailable) "pending_permission" else "pending_reconciliation",
                required = true,
                reasons = buildList {
                    if (exactUnavailable) add("exact_alarm_permission_unavailable")
                    add("scheduler_retry_required")
                },
            )
        }
        val action = (reconciled.data as? Map<*, *>)?.get("action") as? String
        if (action == "cancelled") {
            return capability(capabilityProvider.snapshot(), "not_required", false, emptyList())
        }
        val status = when (reconciliation.scheduleMode) {
            ReminderScheduleMode.Exact -> "scheduled_exact"
            ReminderScheduleMode.Approximate -> "scheduled_approximate"
            null -> {
                enqueueRetry(method, "schedule coordinator returned no completed scheduling mode")
                return capability(
                    snapshot = capabilityProvider.snapshot(),
                    scheduleStatus = "pending_reconciliation",
                    required = true,
                    reasons = listOf("scheduler_retry_required"),
                )
            }
        }
        return capability(
            snapshot = capabilityProvider.snapshot(),
            scheduleStatus = status,
            required = false,
            reasons = if (status == "scheduled_approximate") {
                listOf("exact_alarm_permission_unavailable")
            } else {
                emptyList()
            },
        )
    }

    private fun passiveCapability(
        required: Boolean,
        notificationDeliveryRequired: Boolean,
    ): Map<String, Any?> {
        val snapshot = capabilityProvider.snapshot()
        if (!required) return capability(snapshot, "not_required", false, emptyList())
        return if (notificationDeliveryRequired && !snapshot.canPostNotifications) {
            capability(
                snapshot,
                "pending_permission",
                true,
                listOf("notification_permission_unavailable"),
            )
        } else {
            capability(snapshot, "pending_reconciliation", true, listOf("scheduler_retry_required"))
        }
    }

    private fun capability(
        snapshot: AnniversaryCapabilitySnapshot,
        scheduleStatus: String,
        required: Boolean,
        reasons: List<String>,
    ): Map<String, Any?> = linkedMapOf(
        "schedule_status" to scheduleStatus,
        "schedule_reconciliation_required" to required,
        "notification_permission_status" to snapshot.notificationPermissionStatus,
        "exact_alarm_permission_status" to snapshot.exactAlarmPermissionStatus,
        "degradation_reasons" to reasons.distinct(),
    )

    private fun withReconciliationFlag(
        detail: Map<String, Any?>,
        required: Boolean,
    ): Map<String, Any?> {
        val settings = LinkedHashMap(reminderSettings(detail))
        settings["schedule_reconciliation_required"] = required
        return LinkedHashMap(detail).apply { this["reminder_settings"] = settings }
    }

    @Suppress("UNCHECKED_CAST")
    private fun reminderSettings(detail: Map<String, Any?>): Map<String, Any?> =
        detail["reminder_settings"] as Map<String, Any?>

    private fun requiresNotificationDelivery(settings: Map<String, Any?>): Boolean =
        settings["reminders_enabled"] as Boolean &&
            (settings["active_reminder_count"] as Number).toInt() > 0

    @Suppress("UNCHECKED_CAST")
    private fun objectMap(value: Any?, parent: String): Map<String, Any?> =
        value as? Map<String, Any?>
            ?: throw com.excellentcalendar.excellent_calendar.bridge.contract.NativeContractViolation(
                "$parent must be an object.",
                parent,
            )

    private fun enqueueRetry(method: String, reason: String) {
        logger.log(method, null, "anniversary data committed; reconcile deferred reason=$reason")
        runCatching { reconcileRetryEnqueuer?.invoke() }
    }
}
