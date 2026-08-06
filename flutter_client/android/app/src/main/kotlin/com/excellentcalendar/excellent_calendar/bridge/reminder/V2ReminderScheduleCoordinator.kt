package com.excellentcalendar.excellent_calendar.bridge.reminder

import com.excellentcalendar.excellent_calendar.android.alarm.CancelResult
import com.excellentcalendar.excellent_calendar.android.alarm.DispatchAlarmScheduler
import com.excellentcalendar.excellent_calendar.android.alarm.ScheduleResult
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeContractViolation
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReconcileReminderScheduleContract
import com.excellentcalendar.excellent_calendar.bridge.contract.V2ReminderItem
import com.excellentcalendar.excellent_calendar.bridge.contract.V2SchedulableBatch
import com.excellentcalendar.excellent_calendar.bridge.contract.V2SchedulableCursor
import com.excellentcalendar.excellent_calendar.bridge.native.NativeReminderBridge
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

class V2ReminderScheduleCoordinator(
    private val nativeBridge: NativeReminderBridge,
    private val alarmScheduler: DispatchAlarmScheduler,
    private val deliveryService: V2ReminderDeliverer,
    private val recoveryCoordinator: ReminderRecoveryRunner,
    private val continuationEnqueuer: () -> Unit,
    private val logger: ReminderOrchestrationLogger,
    private val nowUtc: () -> String = { currentUtcInstant() },
    private val elapsedRealtime: () -> Long = { android.os.SystemClock.elapsedRealtime() },
) : ReminderScheduleReconciler {
    override fun reconcile(request: ReconcileReminderScheduleContract, executionBudgetMillis: Long): NativeResultContract =
        ProcessLock.withLock {
            val startedAt = elapsedRealtime()
            val deadline = if (executionBudgetMillis == Long.MAX_VALUE) Long.MAX_VALUE else startedAt + executionBudgetMillis
            if (elapsedRealtime() >= deadline) return@withLock continuationResponse()

            val recovered = recoveryCoordinator.recover(request.trigger) { elapsedRealtime() < deadline }
            val recoveryFailure: NativeResultContract?
            if (!recovered.ok) {
                if (recovered.error?.retryable == true) enqueueContinuation()
                logger.log(
                    "reminder.plan_recovery",
                    null,
                    "failed code=${recovered.error?.code ?: "UNKNOWN"} " +
                        "retryable=${recovered.error?.retryable == true} live_reconcile_continues=true",
                )
                recoveryFailure = recovered
            } else {
                @Suppress("UNCHECKED_CAST")
                if ((recovered.data as? Map<String, Any?>)?.get("continuation_required") == true) {
                    return@withLock continuationResponse()
                }
                recoveryFailure = null
            }

            val currentNow = nowUtc()
            var processed = 0
            var cursor: V2SchedulableCursor? = null
            do {
                val listed = listSchedulable(toAt = currentNow, cursor = cursor, includeScheduled = true, limit = DeliveryBatchSize)
                if (!listed.ok) return@withLock listed
                val batch = V2SchedulableBatch.fromData(listed.data)
                for (reminder in batch.reminders) {
                    if (elapsedRealtime() >= deadline) {
                        val continuation = continuationResponse(processed)
                        return@withLock recoveryFailure ?: continuation
                    }
                    val delivered = deliveryService.deliverReminder(reminder.reminderId, reminder.remindAt)
                    if (!delivered.ok) {
                        if (delivered.error?.retryable == true) enqueueContinuation()
                        return@withLock delivered
                    }
                    processed += 1
                }
                cursor = batch.nextCursor
            } while (cursor != null)

            var conflictRetries = 0
            while (true) {
                val headResult = listSchedulable(fromAt = currentNow, includeScheduled = true, limit = 1)
                if (!headResult.ok) return@withLock headResult
                val head = V2SchedulableBatch.fromData(headResult.data).reminders.firstOrNull()
                if (head == null) {
                    return@withLock when (val cancelled = alarmScheduler.cancel()) {
                        CancelResult.Success -> recoveryFailure ?: success("cancelled", null, processed)
                        is CancelResult.Failure -> NativeResultContract.failure(cancelled.code, cancelled.message, retryable = cancelled.retryable, contractVersion = 2)
                    }
                }
                when (val scheduled = alarmScheduler.schedule(head.remindAt)) {
                    is ScheduleResult.Failure -> return@withLock NativeResultContract.failure(
                        scheduled.code,
                        scheduled.message,
                        details = linkedMapOf("reminder_id" to head.reminderId, "next_remind_at" to head.remindAt),
                        retryable = scheduled.retryable,
                        contractVersion = 2,
                    )
                    ScheduleResult.Success -> {
                        val marked = markScheduled(head)
                        if (marked.ok) {
                            logger.log("reminder.reconcile_schedule", head.reminderId, "trigger_source=${request.trigger.wireValue} next_remind_at=${head.remindAt}")
                            return@withLock recoveryFailure ?: success("scheduled", head.remindAt, processed)
                        }
                        if (marked.error?.code != NativeErrorCodes.ReminderScheduleConflict || conflictRetries++ >= MaxScheduleConflictRetries) {
                            return@withLock marked
                        }
                        logger.log("reminder.reconcile_schedule", head.reminderId, "schedule CAS conflict; reconciling authoritative head")
                    }
                }
            }
            @Suppress("UNREACHABLE_CODE")
            error("Reminder schedule loop terminated unexpectedly.")
        }

    private fun listSchedulable(
        fromAt: String? = null,
        toAt: String? = null,
        cursor: V2SchedulableCursor? = null,
        includeScheduled: Boolean,
        limit: Int,
    ): NativeResultContract {
        val request = linkedMapOf<String, Any?>(
            "from_at" to fromAt,
            "to_at" to toAt,
            "cursor" to cursor?.toMap(),
            "limit" to limit,
            "include_scheduled" to includeScheduled,
            "supported_methods" to listOf("popup"),
        )
        return parse(nativeBridge.listSchedulableReminders(NativeContractJsonCodec.encodeObject(request))) {
            V2SchedulableBatch.fromData(it)
        }
    }

    private fun markScheduled(reminder: V2ReminderItem): NativeResultContract = parse(
        nativeBridge.markReminderScheduled(
            NativeContractJsonCodec.encodeObject(
                linkedMapOf(
                    "reminder_id" to reminder.reminderId,
                    "expected_remind_at" to reminder.remindAt,
                    "scheduled_at" to nowUtc(),
                ),
            ),
        ),
    ) { data -> if (data !is Map<*, *>) throw NativeContractViolation("ReminderResponse must be an object.", "data") }

    private fun parse(json: String, validator: (Any?) -> Unit): NativeResultContract = try {
        NativeResultContract.fromJson(json, 2, validator)
    } catch (error: NativeContractViolation) {
        NativeResultContract.failure(
            NativeErrorCodes.ContractValidationFailed,
            error.message ?: "Reminder scheduling response is malformed.",
            details = linkedMapOf("field" to error.field),
            contractVersion = 2,
        )
    }

    private fun continuationResponse(processed: Int = 0): NativeResultContract {
        val enqueued = enqueueContinuation()
        return success("unchanged", null, processed, continuationEnqueued = enqueued)
    }

    private fun enqueueContinuation(): Boolean = try {
        continuationEnqueuer()
        true
    } catch (error: Throwable) {
        logger.log("reminder.reconcile_schedule", null, "continuation enqueue failed type=${error.javaClass.simpleName}")
        false
    }

    private fun success(
        action: String,
        nextRemindAt: String?,
        processed: Int,
        continuationEnqueued: Boolean = false,
    ): NativeResultContract = NativeResultContract.success(
        linkedMapOf(
            "action" to action,
            "next_remind_at" to nextRemindAt,
            "processed_due_count" to processed,
            "failed_count" to 0,
            "continuation_enqueued" to continuationEnqueued,
            "failed_reminder_ids" to emptyList<String>(),
        ),
        contractVersion = 2,
    )

    companion object {
        private val ProcessLock = ReentrantLock()
        private const val DeliveryBatchSize = 20
        private const val MaxScheduleConflictRetries = 2

        private fun currentUtcInstant(): String = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(Date())
    }
}
