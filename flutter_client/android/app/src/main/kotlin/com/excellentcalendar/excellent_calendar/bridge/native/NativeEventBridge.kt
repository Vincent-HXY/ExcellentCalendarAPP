package com.excellentcalendar.excellent_calendar.bridge.native

interface NativeEventBridge {
    fun createEvent(requestJson: String): String

    fun searchEvents(requestJson: String): String
}
