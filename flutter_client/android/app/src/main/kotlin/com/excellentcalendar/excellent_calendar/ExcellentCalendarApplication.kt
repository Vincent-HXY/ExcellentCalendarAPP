package com.excellentcalendar.excellent_calendar

import android.app.Application
import com.excellentcalendar.excellent_calendar.android.alarm.ReminderWorkScheduler
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderScheduleTrigger
import com.excellentcalendar.excellent_calendar.bridge.native.NativeContractProfile
import com.excellentcalendar.excellent_calendar.bridge.native.NativeContractRuntimeProfile

class ExcellentCalendarApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        ReminderWorkScheduler.ensurePeriodic(this)
        if (NativeContractRuntimeProfile.current == NativeContractProfile.V2) {
            ReminderWorkScheduler.enqueue(this, ReminderScheduleTrigger.AppStart)
        }
    }
}
