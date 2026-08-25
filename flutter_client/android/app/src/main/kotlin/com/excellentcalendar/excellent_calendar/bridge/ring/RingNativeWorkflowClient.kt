package com.excellentcalendar.excellent_calendar.bridge.ring

import android.util.Log
import com.excellentcalendar.excellent_calendar.android.ring.RingItemRecord
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeContractViolation
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorContract
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.V2ResponseContracts
import com.excellentcalendar.excellent_calendar.bridge.native.NativeCalendarCoreBridge

data class RingSnoozeItemOutcome(
    val deliveryId: String,
    val snoozedReminderId: String?,
    val error: NativeErrorContract?,
) {
    val succeeded: Boolean get() = snoozedReminderId != null

    fun toMap(): Map<String, Any?> = linkedMapOf(
        "delivery_id" to deliveryId,
        "status" to if (succeeded) "succeeded" else "failed",
        "snoozed_reminder_id" to snoozedReminderId,
        "error" to error?.toMap(),
    )
}

class RingNativeWorkflowClient(
    private val nativeBridge: NativeCalendarCoreBridge,
) {
    fun snooze(item: RingItemRecord): RingSnoozeItemOutcome {
        val result = try {
            NativeResultContract.fromJson(
                nativeBridge.snoozeReminder(
                    NativeContractJsonCodec.encodeObject(linkedMapOf("source_delivery_id" to item.deliveryId)),
                ),
                2,
            ) { data ->
                val map = data as? Map<*, *> ?: throw NativeContractViolation("SnoozeReminderResponse must be an object.", "data")
                val snoozeMinutes = map["snooze_minutes"] as? Number
                if (
                    map["source_delivery_id"] != item.deliveryId ||
                    snoozeMinutes?.toDouble() != 10.0 ||
                    map["idempotent_replay"] !is Boolean
                ) {
                    throw NativeContractViolation("SnoozeReminderResponse identity is invalid.", "data.source_delivery_id")
                }
                V2ResponseContracts.reminder((map["snoozed_reminder"] as? Map<*, *>)?.entries?.associate { it.key as String to it.value })
            }
        } catch (error: Throwable) {
            Log.e(
                LogTag,
                "operation=reminder.snooze delivery_id=${item.deliveryId} " +
                    "failed type=${error.javaClass.simpleName} message=${error.message ?: "none"}",
                error,
            )
            return RingSnoozeItemOutcome(
                item.deliveryId,
                null,
                NativeErrorContract(NativeErrorCodes.NativeInternalError, "Reminder snooze is unavailable.", null, true),
            )
        }
        if (!result.ok) return RingSnoozeItemOutcome(item.deliveryId, null, result.error)
        @Suppress("UNCHECKED_CAST")
        val data = result.data as Map<String, Any?>
        @Suppress("UNCHECKED_CAST")
        val reminder = data["snoozed_reminder"] as Map<String, Any?>
        return RingSnoozeItemOutcome(item.deliveryId, reminder["reminder_id"] as String, null)
    }

    fun complete(item: RingItemRecord): NativeResultContract {
        return try {
            NativeResultContract.fromJson(
                nativeBridge.completeEvent(
                    NativeContractJsonCodec.encodeObject(
                        linkedMapOf("event_id" to item.eventId, "source" to "manual", "note" to null),
                    ),
                ),
                2,
                V2ResponseContracts::event,
            )
        } catch (error: Throwable) {
            NativeResultContract.failure(
                NativeErrorCodes.NativeInternalError,
                "Event completion is unavailable.",
                retryable = true,
                contractVersion = 2,
            )
        }
    }

    private companion object {
        const val LogTag = "ExcellentCalendarRing"
    }
}
