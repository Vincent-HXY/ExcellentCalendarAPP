package com.excellentcalendar.excellent_calendar.android.alarm

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.excellentcalendar.excellent_calendar.bridge.contract.ReconcileReminderScheduleContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderScheduleTrigger
import java.util.concurrent.TimeUnit

class ReminderQueueWorker(
    appContext: Context,
    params: WorkerParameters,
) : Worker(appContext, params) {
    override fun doWork(): Result {
        val trigger = inputData.getString(InputTrigger)
            ?.let { runCatching { ReminderScheduleTrigger.fromWire(it) }.getOrNull() }
            ?: ReminderScheduleTrigger.PeriodicWorker
        return try {
            val result = ReminderCoordinatorFactory.create(applicationContext).reconcile(
                ReconcileReminderScheduleContract(trigger, force = true),
                executionBudgetMillis = Long.MAX_VALUE,
            )
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
    }
}

object ReminderWorkScheduler {
    private const val PeriodicWorkName = "reminder-queue-watchdog"
    private const val ContinuationWorkName = "reminder-queue-continuation"

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

    fun enqueue(context: Context, trigger: ReminderScheduleTrigger) {
        val request = OneTimeWorkRequestBuilder<ReminderQueueWorker>()
            .setInputData(workDataOf(ReminderQueueWorker.InputTrigger to trigger.wireValue))
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.MINUTES)
            .build()
        WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
            ContinuationWorkName,
            ExistingWorkPolicy.KEEP,
            request,
        )
    }
}
