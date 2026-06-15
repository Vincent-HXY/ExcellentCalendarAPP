package com.excellentcalendar.excellent_calendar.android.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * AlarmManager 的落点 receiver。
 *
 * 本阶段只完成调度注册边界，不创建 Notification 记录，也不展示系统通知。
 */
class ReminderAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != AlarmManagerReminderScheduler.ActionReminderAlarm) {
            return
        }
        val reminderId = intent.getStringExtra(AlarmManagerReminderScheduler.ExtraReminderId)
        Log.d(LogTag, "Reminder alarm received reminder_id=${reminderId ?: "null"}")
    }

    companion object {
        private const val LogTag = "ExcellentCalendarAlarm"
    }
}
