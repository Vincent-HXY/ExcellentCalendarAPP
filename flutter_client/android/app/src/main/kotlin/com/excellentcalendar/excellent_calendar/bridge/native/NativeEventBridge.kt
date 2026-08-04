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

    fun getEventDetail(requestJson: String): String = throw UnsupportedOperationException("event.detail is unavailable")

    fun completeEvent(requestJson: String): String

    fun reopenEvent(requestJson: String): String

    fun listEventOccurrences(requestJson: String): String = throw UnsupportedOperationException("event.list_occurrences is unavailable")

    fun completeEventOccurrence(requestJson: String): String = throw UnsupportedOperationException("event_occurrence.complete is unavailable")

    fun reopenEventOccurrence(requestJson: String): String = throw UnsupportedOperationException("event_occurrence.reopen is unavailable")

    fun skipEventOccurrence(requestJson: String): String = throw UnsupportedOperationException("event_occurrence.skip is unavailable")

    fun cancelEventOccurrence(requestJson: String): String = throw UnsupportedOperationException("event_occurrence.cancel is unavailable")

    fun completeEventSeries(requestJson: String): String = throw UnsupportedOperationException("event_series.complete is unavailable")

    fun reopenEventSeries(requestJson: String): String = throw UnsupportedOperationException("event_series.reopen is unavailable")

    fun cancelEventSeries(requestJson: String): String = throw UnsupportedOperationException("event_series.cancel is unavailable")
}
