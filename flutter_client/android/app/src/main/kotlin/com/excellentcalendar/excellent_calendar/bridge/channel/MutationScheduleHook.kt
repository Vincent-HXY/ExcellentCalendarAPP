package com.excellentcalendar.excellent_calendar.bridge.channel

import com.excellentcalendar.excellent_calendar.bridge.contract.ReconcileReminderScheduleContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderScheduleTrigger
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderScheduleReconciler

/** Post-commit hook: scheduling failure is deferred and never rolls back a committed mutation. */
internal class MutationScheduleHook(
    private val reminderScheduleCoordinator: ReminderScheduleReconciler?,
    private val reconcileRetryEnqueuer: (() -> Unit)?,
    private val logger: NativeBridgeLogger,
) {
    fun afterMutation(method: String) {
        try {
            val reconciled = reminderScheduleCoordinator?.reconcile(
                ReconcileReminderScheduleContract(ReminderScheduleTrigger.Mutation, force = true),
            )
            if (reconciled != null && !reconciled.ok) {
                logger.log(
                    method,
                    reconciled.requestId,
                    "domain mutation committed; reconcile deferred code=${reconciled.error?.code}",
                )
                reconcileRetryEnqueuer?.invoke()
            }
        } catch (error: Throwable) {
            logger.log(
                method,
                null,
                "domain mutation committed; reconcile deferred type=${error.javaClass.simpleName}",
            )
            runCatching { reconcileRetryEnqueuer?.invoke() }
        }
    }
}
