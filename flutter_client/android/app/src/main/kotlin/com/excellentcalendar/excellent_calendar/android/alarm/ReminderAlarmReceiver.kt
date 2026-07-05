package com.excellentcalendar.excellent_calendar.android.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.excellentcalendar.excellent_calendar.android.notification.AndroidNotificationDisplayService
import com.excellentcalendar.excellent_calendar.android.notification.AndroidNotificationRuntime
import com.excellentcalendar.excellent_calendar.bridge.native.AndroidNativeBridgeFactory
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderDeliveryService
import java.util.concurrent.Executors

/**
 * AlarmManager 的落点 receiver。
 *
 * Receiver 使用 goAsync 在后台完成 JNI 查询、系统通知投递和消费状态回写。
 */
class ReminderAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != AlarmManagerReminderScheduler.ActionReminderAlarm) {
            return
        }
        val reminderId = intent.getStringExtra(AlarmManagerReminderScheduler.ExtraReminderId)
        if (reminderId.isNullOrBlank()) return
        val plannedAt = intent.getStringExtra(AlarmManagerReminderScheduler.ExtraPlannedAt)
        val pendingResult = goAsync()
        Executor.execute {
            try {
                val bridge = AndroidNativeBridgeFactory.create(context)
                val service = ReminderDeliveryService(
                    nativeBridge = bridge,
                    notifications = AndroidNotificationDisplayService(context),
                    eventHub = AndroidNotificationRuntime.eventHub,
                    logger = { operation, id, message ->
                        Log.d(LogTag, "operation=$operation reminder_id=${id ?: "null"} $message")
                    },
                )
                val result = service.deliver(reminderId, plannedAt)
                Log.d(LogTag, "Reminder alarm handled reminder_id=$reminderId result=${result.javaClass.simpleName}")
            } catch (error: Throwable) {
                Log.e(LogTag, "Reminder alarm failed reminder_id=$reminderId type=${error.javaClass.simpleName}")
            } finally {
                pendingResult.finish()
            }
        }
    }

    companion object {
        private const val LogTag = "ExcellentCalendarAlarm"
        private val Executor = Executors.newSingleThreadExecutor()
    }
}
