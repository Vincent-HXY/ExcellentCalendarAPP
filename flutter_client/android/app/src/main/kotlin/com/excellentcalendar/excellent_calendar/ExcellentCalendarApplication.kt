package com.excellentcalendar.excellent_calendar

import android.app.Application
import com.excellentcalendar.excellent_calendar.android.alarm.ReminderWorkScheduler

class ExcellentCalendarApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        ReminderWorkScheduler.ensurePeriodic(this)
    }
}
