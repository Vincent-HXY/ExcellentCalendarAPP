package com.excellentcalendar.excellent_calendar.bridge.reminder

import com.excellentcalendar.excellent_calendar.android.alarm.CancelResult
import com.excellentcalendar.excellent_calendar.android.alarm.DispatchAlarmScheduler
import com.excellentcalendar.excellent_calendar.android.alarm.ScheduleResult
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReconcileReminderScheduleContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderResponseContract
import com.excellentcalendar.excellent_calendar.bridge.contract.SchedulableReminderBatch
import com.excellentcalendar.excellent_calendar.bridge.contract.SchedulableReminderCursor
import com.excellentcalendar.excellent_calendar.bridge.native.NativeReminderBridge
import java.time.Instant
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/** Serializes every queue/Alarm reconciliation in this process. Reminder storage remains authoritative. */
class ReminderScheduleCoordinator(
    private val nativeBridge: NativeReminderBridge,
    private val alarmScheduler: DispatchAlarmScheduler,
    private val deliveryService: ReminderDeliveryService,
    private val continuationEnqueuer: () -> Unit,
    private val logger: ReminderOrchestrationLogger,
    private val now: () -> Instant = { Instant.now() },
    private val elapsedRealtime: () -> Long = { android.os.SystemClock.elapsedRealtime() },
) {
    fun reconcile(
        request: ReconcileReminderScheduleContract,
        executionBudgetMillis: Long = DefaultExecutionBudgetMillis,
    ): NativeResultContract = ProcessLock.withLock {
        val startedAt = elapsedRealtime()
        val deadline = if (executionBudgetMillis == Long.MAX_VALUE) Long.MAX_VALUE else startedAt + executionBudgetMillis
        var processedDueCount = 0
        val failedIds = linkedSetOf<String>()
        var continuationEnqueued = false
        var cursor: SchedulableReminderCursor? = null
        val currentNow = now()

        do {
            val listed = listSchedulable(
                toAt = currentNow.toString(),
                cursor = cursor,
                includeFailed = true,
                includeScheduled = true,
                limit = DeliveryBatchSize,
            )
            if (!listed.ok) return@withLock listed
            val batch = SchedulableReminderBatch.fromData(listed.data)
            for (reminder in batch.reminders) {
                if (elapsedRealtime() >= deadline) {
                    continuationEnqueued = enqueueContinuation()
                    return@withLock successResponse(
                        action = "unchanged",
                        nextRemindAt = null,
                        processedDueCount = processedDueCount,
                        failedIds = failedIds,
                        continuationEnqueued = continuationEnqueued,
                    )
                }
                processedDueCount += 1
                when (deliveryService.deliver(reminder.id, reminder.remindAt)) {
                    is ReminderDeliveryResult.Delivered,
                    is ReminderDeliveryResult.Skipped -> Unit
                    is ReminderDeliveryResult.Failed -> failedIds.add(reminder.id)
                }
            }
            cursor = batch.nextCursor
        } while (cursor != null)

        val headResult = listSchedulable(
            fromAt = currentNow.toString(),
            includeFailed = true,
            includeScheduled = true,
            limit = 1,
        )
        if (!headResult.ok) return@withLock headResult
        val head = SchedulableReminderBatch.fromData(headResult.data).reminders.firstOrNull()
        if (head == null) {
            return@withLock when (val cancelled = alarmScheduler.cancel()) {
                CancelResult.Success -> successResponse(
                    action = "cancelled",
                    nextRemindAt = null,
                    processedDueCount = processedDueCount,
                    failedIds = failedIds,
                    continuationEnqueued = continuationEnqueued,
                )
                is CancelResult.Failure -> NativeResultContract.failure(
                    cancelled.code,
                    cancelled.message,
                    retryable = cancelled.retryable,
                )
            }
        }

        when (val scheduled = alarmScheduler.schedule(head.remindAt)) {
            ScheduleResult.Success -> markTimestampScheduled(head.remindAt, failedIds)
            is ScheduleResult.Failure -> {
                markFailed(head.id, scheduled.message)
                return@withLock NativeResultContract.failure(
                    scheduled.code,
                    scheduled.message,
                    details = linkedMapOf("reminder_id" to head.id, "next_remind_at" to head.remindAt),
                    retryable = scheduled.retryable,
                )
            }
        }

        logger.log(
            "reminder.reconcile_schedule",
            null,
            "trigger_source=${request.trigger.wireValue} next_remind_at=${head.remindAt} " +
                "processed_due_count=$processedDueCount failed_count=${failedIds.size} " +
                "continuation_enqueued=$continuationEnqueued duration_ms=${elapsedRealtime() - startedAt}",
        )
        successResponse(
            action = "scheduled",
            nextRemindAt = head.remindAt,
            processedDueCount = processedDueCount,
            failedIds = failedIds,
            continuationEnqueued = continuationEnqueued,
        )
    }

    private fun listSchedulable(
        fromAt: String? = null,
        toAt: String? = null,
        cursor: SchedulableReminderCursor? = null,
        includeFailed: Boolean,
        includeScheduled: Boolean,
        limit: Int,
    ): NativeResultContract {
        val request = linkedMapOf<String, Any?>(
            "limit" to limit,
            "include_failed" to includeFailed,
            "include_scheduled" to includeScheduled,
            "supported_methods" to listOf("popup"),
        )
        if (fromAt != null) request["from_at"] = fromAt
        if (toAt != null) request["to_at"] = toAt
        if (cursor != null) request["cursor"] = cursor.toMap()
        return NativeResultContract.fromJson(
            nativeBridge.listSchedulableReminders(NativeContractJsonCodec.encodeObject(request)),
        ) { SchedulableReminderBatch.fromData(it) }
    }

    private fun markTimestampScheduled(remindAt: String, failedIds: MutableSet<String>) {
        var cursor: SchedulableReminderCursor? = null
        do {
            val listed = listSchedulable(
                fromAt = remindAt,
                toAt = remindAt,
                cursor = cursor,
                includeFailed = true,
                includeScheduled = true,
                limit = StateBatchSize,
            )
            if (!listed.ok) {
                logger.log("reminder.reconcile_schedule", null, "mark batch query failed")
                return
            }
            val batch = SchedulableReminderBatch.fromData(listed.data)
            for (reminder in batch.reminders) {
                val marked = NativeResultContract.fromJson(
                    nativeBridge.markReminderScheduled(
                        NativeContractJsonCodec.encodeObject(
                            linkedMapOf("id" to reminder.id, "scheduled_at" to now().toString()),
                        ),
                    ),
                    ReminderResponseContract::validate,
                )
                if (!marked.ok) failedIds.add(reminder.id)
            }
            cursor = batch.nextCursor
        } while (cursor != null)
    }

    private fun markFailed(reminderId: String, reason: String) {
        try {
            NativeResultContract.fromJson(
                nativeBridge.markReminderFailed(
                    NativeContractJsonCodec.encodeObject(
                        linkedMapOf("id" to reminderId, "failure_reason" to reason),
                    ),
                ),
                ReminderResponseContract::validate,
            )
        } catch (error: Throwable) {
            logger.log("reminder.reconcile_schedule", reminderId, "mark_failed failed type=${error.javaClass.simpleName}")
        }
    }

    private fun enqueueContinuation(): Boolean = try {
        continuationEnqueuer()
        true
    } catch (error: Throwable) {
        logger.log("reminder.reconcile_schedule", null, "continuation enqueue failed type=${error.javaClass.simpleName}")
        false
    }

    private fun successResponse(
        action: String,
        nextRemindAt: String?,
        processedDueCount: Int,
        failedIds: Set<String>,
        continuationEnqueued: Boolean,
    ): NativeResultContract = NativeResultContract.success(
        linkedMapOf(
            "action" to action,
            "next_remind_at" to nextRemindAt,
            "processed_due_count" to processedDueCount,
            "failed_count" to failedIds.size,
            "continuation_enqueued" to continuationEnqueued,
            "failed_reminder_ids" to failedIds.toList(),
        ),
    )

    companion object {
        private val ProcessLock = ReentrantLock()
        const val DefaultExecutionBudgetMillis = 8_000L
        private const val DeliveryBatchSize = 64
        private const val StateBatchSize = 128
    }
}
