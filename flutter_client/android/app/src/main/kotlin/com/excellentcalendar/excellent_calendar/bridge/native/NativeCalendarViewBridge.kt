package com.excellentcalendar.excellent_calendar.bridge.native

/** Narrow Kotlin access to the read-only Calendar View C++ boundary. */
interface NativeCalendarViewBridge {
    fun calendarRangeSummary(requestJson: String): String = unavailable()

    fun calendarListDayItems(requestJson: String): String = unavailable()

    private fun unavailable(): Nothing =
        throw UnsupportedOperationException("Calendar View bridge is unavailable.")
}

/** Frozen JNI method names shared by production glue and ABI verification. */
object CalendarViewJniSymbolManifest {
    val methods: List<String> = listOf(
        "nativeCalendarRangeSummaryV2",
        "nativeCalendarListDayItemsV2",
    )
}
