package com.excellentcalendar.excellent_calendar.bridge.reminder

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.HabitContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeContractViolation
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReconcileReminderScheduleContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderScheduleTrigger
import com.excellentcalendar.excellent_calendar.bridge.native.NativeBridgeUnavailableException
import com.excellentcalendar.excellent_calendar.bridge.native.NativeHabitBridge
import com.excellentcalendar.excellent_calendar.bridge.runtime.DeviceTimezoneProvider

internal data class HabitReconcileRun(
    val result: NativeResultContract,
    val scheduleReconciliationRequired: Boolean,
    val continuationRequired: Boolean,
)

internal data class HabitReconcileContinuation(
    val cursor: String,
    val trigger: ReminderScheduleTrigger,
    val timezone: String,
    val dispatcherPlannedAt: String? = null,
)

/** Runs the Habit-only same-day cursor before the shared Reminder queue. */
internal class HabitReminderReconciler(
    private val bridge: NativeHabitBridge,
    private val timezoneProvider: DeviceTimezoneProvider,
    private val continuationEnqueuer: (HabitReconcileContinuation) -> Unit,
    private val logger: ReminderOrchestrationLogger,
) {
    fun reconcile(
        trigger: ReminderScheduleTrigger,
        initialCursor: String? = null,
        dispatcherPlannedAt: String? = null,
    ): HabitReconcileRun {
        val timezone = timezoneProvider.currentTimezone()
        var cursor: String? = initialCursor
        val seen = linkedSetOf<String>()
        var pages = 0
        var processed = 0
        var scheduleRequired = false
        do {
            if (pages >= MaxPages || processed >= MaxProcessed) {
                val enqueued = enqueueContinuation(
                    HabitReconcileContinuation(
                        cursor = checkNotNull(cursor),
                        trigger = trigger,
                        timezone = timezone,
                        dispatcherPlannedAt = dispatcherPlannedAt,
                    ),
                )
                if (!enqueued) {
                    return HabitReconcileRun(
                        NativeResultContract.failure(
                            NativeErrorCodes.NativeInternalError,
                            "Habit reconciliation continuation could not be scheduled.",
                            details = linkedMapOf("operation" to "habit.reconcile_reminders"),
                            retryable = true,
                            contractVersion = 2,
                        ),
                        scheduleRequired,
                        false,
                    )
                }
                return HabitReconcileRun(success(processed, true, true), scheduleRequired, true)
            }
            val request = HabitContracts.reconcileRequest(
                timezone = timezone,
                trigger = habitTrigger(trigger),
                cursor = cursor,
                limit = PageLimit,
            )
            val nativeResult = try {
                NativeResultContract.fromJson(
                    bridge.reconcileHabitReminders(request.toJson()),
                    2,
                ) { data -> HabitContracts.reconcileResponse(data, PageLimit) }
            } catch (error: NativeContractViolation) {
                NativeResultContract.failure(
                    NativeErrorCodes.ContractValidationFailed,
                    error.message ?: "Habit reconciliation response is malformed.",
                    details = linkedMapOf("field" to error.field),
                    contractVersion = 2,
                )
            } catch (error: NativeBridgeUnavailableException) {
                nativeUnavailable(error)
            } catch (error: UnsatisfiedLinkError) {
                nativeUnavailable(error)
            } catch (error: Throwable) {
                logger.log("habit.reconcile_reminders", null, "native call failed type=${error.javaClass.simpleName}")
                NativeResultContract.failure(
                    NativeErrorCodes.NativeInternalError,
                    "Native calendar core bridge call failed.",
                    details = linkedMapOf("reason" to error.javaClass.simpleName),
                    contractVersion = 2,
                )
            }
            if (!nativeResult.ok) return HabitReconcileRun(nativeResult, scheduleRequired, false)
            val page = HabitContracts.reconcileResponse(nativeResult.data, PageLimit)
            pages += 1
            processed += page.processedCount
            scheduleRequired = scheduleRequired || page.scheduleReconciliationRequired
            if (!page.hasMore) {
                return HabitReconcileRun(success(processed, false, false), scheduleRequired, false)
            }
            val next = page.nextCursor!!
            if (next == cursor || !seen.add(next)) {
                logger.log("habit.reconcile_reminders", null, "cursor did not advance; wake stopped")
                return HabitReconcileRun(
                    NativeResultContract.failure(
                        NativeErrorCodes.ContractValidationFailed,
                        "Habit reconciliation cursor did not advance.",
                        details = linkedMapOf("field" to "next_cursor"),
                        contractVersion = 2,
                    ),
                    scheduleRequired,
                    false,
                )
            }
            cursor = next
        } while (true)
    }

    private fun success(processed: Int, budgetReached: Boolean, continuation: Boolean) = NativeResultContract.success(
        linkedMapOf(
            "processed_count" to processed,
            "budget_reached" to budgetReached,
            "continuation_enqueued" to continuation,
        ),
        contractVersion = 2,
    )

    private fun enqueueContinuation(continuation: HabitReconcileContinuation): Boolean = try {
        continuationEnqueuer(continuation)
        true
    } catch (error: Throwable) {
        logger.log("habit.reconcile_reminders", null, "continuation enqueue failed type=${error.javaClass.simpleName}")
        false
    }

    private fun nativeUnavailable(error: Throwable): NativeResultContract {
        logger.log("habit.reconcile_reminders", null, "native unavailable type=${error.javaClass.simpleName}")
        return NativeResultContract.failure(
            NativeErrorCodes.NativeInternalError,
            "Native calendar core bridge is unavailable.",
            details = linkedMapOf("reason" to error.javaClass.simpleName),
            contractVersion = 2,
        )
    }

    private fun habitTrigger(trigger: ReminderScheduleTrigger): String = when (trigger) {
        ReminderScheduleTrigger.AppStart -> "app_start"
        ReminderScheduleTrigger.BootCompleted -> "device_boot"
        ReminderScheduleTrigger.PackageReplaced -> "app_update"
        ReminderScheduleTrigger.DateChanged -> "date_changed"
        ReminderScheduleTrigger.TimeChanged -> "time_changed"
        ReminderScheduleTrigger.TimezoneChanged -> "timezone_changed"
        ReminderScheduleTrigger.ManualRetry -> "permission_restored"
        ReminderScheduleTrigger.Mutation,
        ReminderScheduleTrigger.AppResume,
        ReminderScheduleTrigger.PeriodicWorker,
        ReminderScheduleTrigger.AlarmFired,
        -> "manual_retry"
    }

    companion object {
        const val PageLimit = 100
        const val MaxPages = 20
        const val MaxProcessed = 2_000
    }
}

/** Keeps the shared Alarm queue authoritative after Habit materialization/cancellation. */
internal class HabitAwareReminderScheduleReconciler(
    private val habit: HabitReminderReconciler,
    private val shared: ReminderScheduleReconciler,
    private val initialHabitCursor: String? = null,
) : ReminderScheduleReconciler {
    override fun reconcile(request: ReconcileReminderScheduleContract, executionBudgetMillis: Long): NativeResultContract {
        val habitRun = habit.reconcile(request.trigger, initialHabitCursor)
        if (habitRun.continuationRequired) {
            return habitRun.result
        }
        val sharedResult = shared.reconcile(request, executionBudgetMillis)
        return when {
            !sharedResult.ok -> sharedResult
            !habitRun.result.ok -> habitRun.result
            else -> sharedResult
        }
    }

    override fun reconcileWithOutcome(
        request: ReconcileReminderScheduleContract,
        executionBudgetMillis: Long,
    ): ReminderScheduleReconciliation {
        val habitRun = habit.reconcile(request.trigger, initialHabitCursor)
        if (habitRun.continuationRequired) {
            return ReminderScheduleReconciliation(
                result = habitRun.result,
                scheduleMode = null,
            )
        }
        val sharedResult = shared.reconcileWithOutcome(request, executionBudgetMillis)
        return when {
            !sharedResult.result.ok -> sharedResult
            !habitRun.result.ok -> ReminderScheduleReconciliation(
                result = habitRun.result,
                scheduleMode = sharedResult.scheduleMode,
            )
            else -> sharedResult
        }
    }

    override fun reconcileDispatcherAlarm(
        plannedAt: String,
        executionBudgetMillis: Long,
    ): NativeResultContract {
        val habitRun = habit.reconcile(
            ReminderScheduleTrigger.AlarmFired,
            initialHabitCursor,
            dispatcherPlannedAt = plannedAt,
        )
        if (!habitRun.result.ok || habitRun.continuationRequired) {
            return habitRun.result
        }
        return shared.reconcileDispatcherAlarm(plannedAt, executionBudgetMillis)
    }
}
