package com.excellentcalendar.excellent_calendar.android.alarm

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.lifecycle.Observer
import androidx.work.BackoffPolicy
import androidx.work.Data
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.Operation
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.excellentcalendar.excellent_calendar.bridge.contract.ReconcileReminderScheduleContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderScheduleTrigger
import com.excellentcalendar.excellent_calendar.bridge.reminder.HabitReconcileContinuation
import com.excellentcalendar.excellent_calendar.bridge.runtime.AndroidDeviceTimezoneProvider
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class ReminderQueueWorker(
    appContext: Context,
    params: WorkerParameters,
) : Worker(appContext, params) {
    override fun doWork(): Result {
        val trigger = inputData.getString(InputTrigger)
            ?.let { runCatching { ReminderScheduleTrigger.fromWire(it) }.getOrNull() }
            ?: ReminderScheduleTrigger.PeriodicWorker
        val storedCursor = inputData.getString(InputHabitCursor)
            ?.takeIf { it.isNotBlank() && it.length <= 512 }
        val storedTimezone = inputData.getString(InputHabitTimezone)
        val currentTimezone = AndroidDeviceTimezoneProvider.currentTimezone()
        val timezoneChanged = storedCursor != null && storedTimezone != currentTimezone
        val initialCursor = storedCursor?.takeUnless { timezoneChanged }
        val effectiveTrigger = if (timezoneChanged) {
            ReminderScheduleTrigger.TimezoneChanged
        } else {
            trigger
        }
        val dispatcherPlannedAt = inputData.getString(InputDispatcherPlannedAt)
            ?.takeUnless { timezoneChanged }
        return try {
            val coordinator = ReminderCoordinatorFactory.create(
                applicationContext,
                initialHabitCursor = initialCursor,
            )
            val result = if (dispatcherPlannedAt != null) {
                coordinator.reconcileDispatcherAlarm(
                    dispatcherPlannedAt,
                    executionBudgetMillis = Long.MAX_VALUE,
                )
            } else {
                coordinator.reconcile(
                    ReconcileReminderScheduleContract(effectiveTrigger, force = true),
                    executionBudgetMillis = Long.MAX_VALUE,
                )
            }
            when {
                result.ok -> Result.success()
                result.error?.code == "EXACT_ALARM_PERMISSION_DENIED" -> Result.success()
                result.error?.retryable == true -> Result.retry()
                else -> Result.failure()
            }
        } catch (_: Throwable) {
            Result.retry()
        }
    }

    companion object {
        const val InputTrigger = "trigger_source"
        const val InputHabitCursor = "habit_reconciliation_cursor"
        const val InputHabitTimezone = "habit_reconciliation_timezone"
        const val InputDispatcherPlannedAt = "dispatcher_planned_at"
    }
}

object ReminderWorkScheduler {
    private const val PeriodicWorkName = "reminder-queue-watchdog"
    private const val ContinuationWorkName = "reminder-queue-continuation"
    private const val ContinuationEnqueueTimeoutSeconds = 10L

    internal val ContinuationAppendPolicy = ExistingWorkPolicy.APPEND_OR_REPLACE

    fun ensurePeriodic(context: Context) {
        val request = PeriodicWorkRequestBuilder<ReminderQueueWorker>(
            12,
            TimeUnit.HOURS,
            1,
            TimeUnit.HOURS,
        ).setInputData(workDataOf(ReminderQueueWorker.InputTrigger to ReminderScheduleTrigger.PeriodicWorker.wireValue))
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.MINUTES)
            .build()
        WorkManager.getInstance(context.applicationContext).enqueueUniquePeriodicWork(
            PeriodicWorkName,
            ExistingPeriodicWorkPolicy.UPDATE,
            request,
        )
    }

    fun enqueueContinuation(context: Context) {
        enqueue(context, ReminderScheduleTrigger.AlarmFired)
    }

    /**
     * Appends a bounded reconciliation continuation after the currently running
     * unique-work chain and waits only for WorkManager to persist the request.
     * Callers run on the reminder worker/native executor, never the main thread.
     */
    fun enqueueConfirmedContinuation(context: Context): Boolean {
        val request = request(ReminderScheduleTrigger.AlarmFired)
        return enqueueConfirmed(context, request)
    }

    internal fun enqueueConfirmedHabitContinuation(
        context: Context,
        continuation: HabitReconcileContinuation,
    ): Boolean {
        val request = OneTimeWorkRequestBuilder<ReminderQueueWorker>()
            .setInputData(habitContinuationInputData(continuation))
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.MINUTES)
            .build()
        return enqueueConfirmed(context, request)
    }

    internal fun habitContinuationInputData(continuation: HabitReconcileContinuation): Data =
        Data.Builder()
            .putString(ReminderQueueWorker.InputTrigger, continuation.trigger.wireValue)
            .putString(ReminderQueueWorker.InputHabitCursor, continuation.cursor)
            .putString(ReminderQueueWorker.InputHabitTimezone, continuation.timezone)
            .apply {
                continuation.dispatcherPlannedAt?.let {
                    putString(ReminderQueueWorker.InputDispatcherPlannedAt, it)
                }
            }
            .build()

    private fun enqueueConfirmed(
        context: Context,
        request: androidx.work.OneTimeWorkRequest,
    ): Boolean {
        return runCatching {
            val operation = WorkManager.getInstance(context.applicationContext)
                .enqueueUniqueWork(
                    ContinuationWorkName,
                    ContinuationAppendPolicy,
                    request,
                )
            awaitPersistence(operation)
        }.getOrDefault(false)
    }

    fun enqueue(context: Context, trigger: ReminderScheduleTrigger) {
        WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
            ContinuationWorkName,
            ExistingWorkPolicy.KEEP,
            request(trigger),
        )
    }

    private fun request(trigger: ReminderScheduleTrigger) =
        OneTimeWorkRequestBuilder<ReminderQueueWorker>()
            .setInputData(workDataOf(ReminderQueueWorker.InputTrigger to trigger.wireValue))
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.MINUTES)
            .build()

    private fun awaitPersistence(operation: Operation): Boolean {
        if (Looper.myLooper() == Looper.getMainLooper()) return false
        val completed = CountDownLatch(1)
        val succeeded = AtomicBoolean(false)
        val observer = Observer<Operation.State> { state ->
            when {
                state is Operation.State.SUCCESS -> {
                    succeeded.set(true)
                    completed.countDown()
                }

                state is Operation.State.FAILURE -> completed.countDown()
            }
        }
        val handler = Handler(Looper.getMainLooper())
        if (!handler.post { operation.state.observeForever(observer) }) return false
        val finished = try {
            completed.await(ContinuationEnqueueTimeoutSeconds, TimeUnit.SECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            false
        }
        handler.post { operation.state.removeObserver(observer) }
        return finished && succeeded.get()
    }
}
