package com.excellentcalendar.excellent_calendar.bridge.native

/** Production Calendar View adapter. Runtime ownership and loading stay in the aggregate bridge. */
class JniCalendarViewBridge internal constructor(
    private val invoke: (symbol: String, requestJson: String) -> String,
) : NativeCalendarViewBridge {
    override fun calendarRangeSummary(requestJson: String): String =
        invoke("nativeCalendarRangeSummaryV2", requestJson)

    override fun calendarListDayItems(requestJson: String): String =
        invoke("nativeCalendarListDayItemsV2", requestJson)
}
