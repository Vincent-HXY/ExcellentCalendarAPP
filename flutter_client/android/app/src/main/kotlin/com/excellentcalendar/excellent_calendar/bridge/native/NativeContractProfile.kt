package com.excellentcalendar.excellent_calendar.bridge.native

import com.excellentcalendar.excellent_calendar.BuildConfig

enum class NativeContractProfile(val contractVersion: Int) {
    V1(1),
    V2(2),
}

object NativeContractRuntimeProfile {
    val current: NativeContractProfile
        get() = if (BuildConfig.CALENDAR_CORE_V2_ENABLED) NativeContractProfile.V2 else NativeContractProfile.V1
}
