package com.excellentcalendar.excellent_calendar.bridge.native

/** Kotlin side notification-log access to C++ Calendar Core. */
interface NativeNotificationBridge {
    fun createNotification(requestJson: String): String

    fun consumeReminderAfterDelivery(requestJson: String): String
}
