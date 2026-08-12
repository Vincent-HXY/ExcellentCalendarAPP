package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec

class V2JsonRequest internal constructor(val value: Map<String, Any?>) {
    fun toJson(): String = NativeContractJsonCodec.encodeObject(value)
}

/**
 * Compatibility facade for existing MethodChannel call sites.
 *
 * Module-specific validation lives in the corresponding `*V2Contracts` object so adding a
 * domain does not grow this facade into another cross-domain contract implementation.
 */
object V2RequestContracts {
    fun createEvent(arguments: Any?): V2JsonRequest = EventV2Contracts.create(arguments)

    fun updateEvent(arguments: Any?): V2JsonRequest = EventV2Contracts.update(arguments)

    fun deleteEvent(arguments: Any?): V2JsonRequest = EventV2Contracts.delete(arguments)

    fun eventId(arguments: Any?, parent: String = "GetEventDetailRequest"): V2JsonRequest =
        EventV2Contracts.id(arguments, parent)

    fun listOccurrences(arguments: Any?): V2JsonRequest = OccurrenceV2Contracts.list(arguments)

    fun occurrenceOperation(arguments: Any?): V2JsonRequest = OccurrenceV2Contracts.operation(arguments)

    fun seriesOperation(arguments: Any?): V2JsonRequest = OccurrenceV2Contracts.seriesOperation(arguments)

    fun searchEvent(arguments: Any?): V2JsonRequest = EventV2Contracts.search(arguments)

    fun completeEvent(arguments: Any?): V2JsonRequest = EventV2Contracts.complete(arguments)

    fun reopenEvent(arguments: Any?): V2JsonRequest = EventV2Contracts.reopen(arguments)

    fun createReminder(arguments: Any?): V2JsonRequest = ReminderV2Contracts.create(arguments)

    fun updateReminder(arguments: Any?): V2JsonRequest = ReminderV2Contracts.update(arguments)

    fun cancelReminder(arguments: Any?): V2JsonRequest = ReminderV2Contracts.cancel(arguments)

    fun listReminders(arguments: Any?): V2JsonRequest = ReminderV2Contracts.list(arguments)

    fun passthrough(arguments: Any?, parent: String): V2JsonRequest =
        V2ContractPrimitives.request(arguments, parent) { }
}

/** Existing response-validator facade retained for source and behavior compatibility. */
object V2ResponseContracts {
    fun event(data: Any?) = EventV2Contracts.response(data)

    fun eventDetail(data: Any?) = EventV2Contracts.detailResponse(data)

    fun eventList(data: Any?) = EventV2Contracts.listResponse(data)

    fun occurrence(data: Any?) = OccurrenceV2Contracts.response(data)

    fun occurrenceState(data: Any?) = OccurrenceV2Contracts.stateResponse(data)

    fun occurrenceList(data: Any?) = OccurrenceV2Contracts.listResponse(data)

    fun reminder(data: Any?) = ReminderV2Contracts.response(data)

    fun reminderList(data: Any?) = ReminderV2Contracts.listResponse(data)
}
