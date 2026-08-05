package com.excellentcalendar.excellent_calendar.bridge.runtime

import java.time.ZoneId

fun interface DeviceTimezoneProvider {
    fun currentTimezone(): String
}

object AndroidDeviceTimezoneProvider : DeviceTimezoneProvider {
    override fun currentTimezone(): String = ZoneId.systemDefault().id
}
