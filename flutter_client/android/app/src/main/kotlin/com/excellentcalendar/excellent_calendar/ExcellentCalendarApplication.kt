package com.excellentcalendar.excellent_calendar

import android.app.Application
import com.excellentcalendar.excellent_calendar.android.alarm.ReminderWorkScheduler
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderScheduleTrigger
import com.excellentcalendar.excellent_calendar.bridge.native.NativeContractProfile
import com.excellentcalendar.excellent_calendar.bridge.native.NativeContractRuntimeProfile
import com.excellentcalendar.excellent_calendar.android.notification.AndroidNotificationChannelManager
import com.excellentcalendar.excellent_calendar.android.ring.RingRuntimeProvider

class ExcellentCalendarApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        runCatching { AndroidNotificationChannelManager(this).ensureChannels() }
        if (NativeContractRuntimeProfile.current == NativeContractProfile.V2) {
            RingRuntimeProvider.get(this)
        }
        ReminderWorkScheduler.ensurePeriodic(this)
        if (NativeContractRuntimeProfile.current == NativeContractProfile.V2) {
            ReminderWorkScheduler.enqueue(this, ReminderScheduleTrigger.AppStart)
        }
    }
}
