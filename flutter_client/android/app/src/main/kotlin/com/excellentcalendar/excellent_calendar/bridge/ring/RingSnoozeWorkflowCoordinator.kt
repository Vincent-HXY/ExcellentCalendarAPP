package com.excellentcalendar.excellent_calendar.bridge.ring

import com.excellentcalendar.excellent_calendar.android.ring.RingItemRecord
import com.excellentcalendar.excellent_calendar.bridge.contract.ActiveRingItemsContract
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract

/**
 * Keeps the durable C++ snooze mutation and Android's active-session cleanup in one ordered workflow.
 * Scheduling remains a post-commit side effect: a failure there must never fabricate a failed snooze.
 */
class RingSnoozeWorkflowCoordinator(
    private val manager: RingSessionManager,
    private val snoozeItem: (RingItemRecord) -> RingSnoozeItemOutcome,
    private val afterSnoozeCommitted: () -> Boolean,
) {
    fun snooze(request: ActiveRingItemsContract): NativeResultContract {
        manager.validate(request)?.let { return it }
        return execute(manager.items(request.deliveryIds))
    }

    fun snoozeFromNotification(deliveryIds: List<String>): NativeResultContract {
        val items = manager.items(deliveryIds)
        if (items.isEmpty()) {
            return NativeResultContract.failure(
                NativeErrorCodes.RingItemNotFound,
                "No requested ring item exists.",
                retryable = false,
                contractVersion = 2,
            )
        }
        return execute(items)
    }

    private fun execute(items: List<RingItemRecord>): NativeResultContract {
        val outcomes = items.map(snoozeItem)
        val succeeded = outcomes.filter { it.succeeded }
        if (succeeded.isNotEmpty()) {
            val removed = manager.remove(succeeded.map { it.deliveryId })
            val scheduleReady = runCatching(afterSnoozeCommitted).getOrDefault(false)
            if (!removed.ok) {
                return NativeResultContract.failure(
                    removed.error?.code ?: NativeErrorCodes.RingSettingsStorageFailed,
                    "Snooze reminders were created, but active ring cleanup is pending. Retry to finish local cleanup.",
                    details = linkedMapOf(
                        "snooze_committed" to true,
                        "session_cleanup_pending" to true,
                        "committed_delivery_ids" to succeeded.map { it.deliveryId },
                        "snoozed_reminder_ids" to succeeded.mapNotNull { it.snoozedReminderId },
                    ),
                    retryable = true,
                    contractVersion = 2,
                )
            }
            if (!scheduleReady) {
                return NativeResultContract.failure(
                    NativeErrorCodes.AlarmScheduleFailed,
                    "Snooze reminders were created and the current ring was updated, but Android scheduling is pending recovery.",
                    details = linkedMapOf(
                        "snooze_committed" to true,
                        "session_cleanup_pending" to false,
                        "schedule_reconcile_deferred" to true,
                        "committed_delivery_ids" to succeeded.map { it.deliveryId },
                        "snoozed_reminder_ids" to succeeded.mapNotNull { it.snoozedReminderId },
                    ),
                    retryable = true,
                    contractVersion = 2,
                )
            }
        }
        return NativeResultContract.success(
            linkedMapOf(
                "results" to outcomes.map { it.toMap() },
                "succeeded_count" to succeeded.size,
                "failed_count" to outcomes.size - succeeded.size,
                "state" to manager.currentSnapshot(),
            ),
            contractVersion = 2,
        )
    }
}
