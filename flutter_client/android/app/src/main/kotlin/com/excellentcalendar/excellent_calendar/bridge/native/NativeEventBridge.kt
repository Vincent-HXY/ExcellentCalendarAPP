package com.excellentcalendar.excellent_calendar.bridge.native

/**
 * Kotlin side event-module access to C++ Calendar Core.
 *
 * The bridge intentionally passes JSON strings instead of exposing C++ objects:
 * Flutter/Dart, Kotlin, and C++ do not share an object model, while JSON is the
 * stable boundary format defined by contracts.
 */
interface NativeEventBridge {
    fun createEvent(requestJson: String): String

    fun updateEvent(requestJson: String): String

    fun deleteEvent(requestJson: String): String

    fun searchEvents(requestJson: String): String

    fun completeEvent(requestJson: String): String

    fun reopenEvent(requestJson: String): String
}
