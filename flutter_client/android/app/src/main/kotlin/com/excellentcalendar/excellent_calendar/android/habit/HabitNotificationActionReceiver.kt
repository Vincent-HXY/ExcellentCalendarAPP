package com.excellentcalendar.excellent_calendar.android.habit

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.excellentcalendar.excellent_calendar.android.alarm.ReminderCoordinatorFactory
import com.excellentcalendar.excellent_calendar.android.alarm.ReminderWorkScheduler
import com.excellentcalendar.excellent_calendar.android.notification.AndroidNotificationDisplayService
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.HabitContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReconcileReminderScheduleContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderScheduleTrigger
import com.excellentcalendar.excellent_calendar.bridge.native.AndroidNativeBridgeFactory
import com.excellentcalendar.excellent_calendar.bridge.runtime.AndroidDeviceTimezoneProvider
import java.util.concurrent.TimeUnit

class HabitNotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ActionComplete) return
        val json = intent.getStringExtra(ExtraPayloadJson) ?: return
        val payload = try {
            HabitContracts.actionPayload(NativeContractJsonCodec.decodeObject(json))
        } catch (_: Throwable) {
            Log.w(LogTag, "Habit notification action payload was rejected")
            return
        }
        HabitNotificationActionWorkScheduler.enqueue(context.applicationContext, payload)
    }

    companion object {
        const val ActionComplete = "com.excellentcalendar.excellent_calendar.action.HABIT_COMPLETE"
        const val ExtraPayloadJson = "habit_action_payload_json"
        private const val LogTag = "ExcellentCalendarHabit"
    }
}

class HabitNotificationActionWorker(
    appContext: Context,
    params: WorkerParameters,
) : Worker(appContext, params) {
    override fun doWork(): Result {
        val payload = try {
            HabitContracts.actionPayload(
                NativeContractJsonCodec.decodeObject(inputData.getString(InputPayloadJson) ?: return Result.failure()),
            )
        } catch (_: Throwable) {
            return Result.failure()
        }
        val bridge = AndroidNativeBridgeFactory.create(applicationContext)
        val command = try {
            HabitContracts.notificationActionCommand(payload, AndroidDeviceTimezoneProvider.currentTimezone())
        } catch (_: Throwable) {
            return Result.failure()
        }
        val committed = try {
            NativeResultContract.fromJson(bridge.checkInHabit(command.toJson()), 2, HabitContracts::checkInCommit)
        } catch (_: Throwable) {
            return Result.retry()
        }
        if (!committed.ok) return if (committed.error?.retryable == true) Result.retry() else Result.failure()

        AndroidNotificationDisplayService(applicationContext).cancelDelivery(payload.getValue("delivery_id") as String)
        val reconciled = try {
            ReminderCoordinatorFactory.create(applicationContext).reconcile(
                ReconcileReminderScheduleContract(ReminderScheduleTrigger.Mutation, force = true),
                executionBudgetMillis = Long.MAX_VALUE,
            )
        } catch (_: Throwable) {
            ReminderWorkScheduler.enqueueContinuation(applicationContext)
            return Result.retry()
        }
        return if (reconciled.ok) Result.success() else if (reconciled.error?.retryable == true) Result.retry() else Result.failure()
    }

    companion object {
        const val InputPayloadJson = "habit_action_payload_json"
    }
}

object HabitNotificationActionWorkScheduler {
    fun enqueue(context: Context, payload: Map<String, Any?>) {
        val actionId = payload.getValue("action_id") as String
        val data = Data.Builder()
            .putString(HabitNotificationActionWorker.InputPayloadJson, NativeContractJsonCodec.encodeObject(payload))
            .build()
        val request = OneTimeWorkRequestBuilder<HabitNotificationActionWorker>()
            .setInputData(data)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .build()
        WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
            "habit-notification-action:$actionId",
            ExistingWorkPolicy.KEEP,
            request,
        )
    }
}
