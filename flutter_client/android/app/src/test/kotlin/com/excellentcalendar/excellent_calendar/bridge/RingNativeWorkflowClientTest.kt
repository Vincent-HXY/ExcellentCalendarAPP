package com.excellentcalendar.excellent_calendar.bridge

import com.excellentcalendar.excellent_calendar.android.ring.RingItemRecord
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.native.NativeCalendarCoreBridge
import com.excellentcalendar.excellent_calendar.bridge.ring.RingNativeWorkflowClient
import java.lang.reflect.Proxy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RingNativeWorkflowClientTest {
    @Test
    fun acceptsIntegralJsonNumberFromCppSnoozeResponse() {
        val reminderId = "66666666-6666-4666-8666-666666666666"
        val bridge = Proxy.newProxyInstance(
            NativeCalendarCoreBridge::class.java.classLoader,
            arrayOf(NativeCalendarCoreBridge::class.java),
        ) { proxy, method, arguments ->
            when (method.name) {
                "toString" -> "CppNumericRingNativeBridge"
                "hashCode" -> System.identityHashCode(proxy)
                "equals" -> proxy === arguments?.firstOrNull()
                "snoozeReminder" -> NativeContractJsonCodec.encodeObject(
                    linkedMapOf(
                        "ok" to true,
                        "data" to linkedMapOf(
                            "source_delivery_id" to item().deliveryId,
                            "snooze_minutes" to 10.0,
                            "snoozed_reminder" to reminder(reminderId),
                            "idempotent_replay" to false,
                        ),
                        "error" to null,
                        "contract_version" to 2,
                        "request_id" to "77777777-7777-4777-8777-777777777777",
                    ),
                )
                else -> throw AssertionError("Unexpected bridge call: ${method.name}")
            }
        } as NativeCalendarCoreBridge

        val outcome = RingNativeWorkflowClient(bridge).snooze(item())

        assertTrue(outcome.succeeded)
        assertEquals(reminderId, outcome.snoozedReminderId)
        assertNull(outcome.error)
    }

    @Test
    fun unavailableSnoozeJniReturnsFailureInsteadOfFabricatingReminder() {
        val outcome = RingNativeWorkflowClient(unavailableBridge()).snooze(item())

        assertFalse(outcome.succeeded)
        assertNull(outcome.snoozedReminderId)
        assertEquals(NativeErrorCodes.NativeInternalError, outcome.error?.code)
    }

    @Test
    fun unavailableCompleteJniReturnsFailureInsteadOfFabricatingEventCompletion() {
        val result = RingNativeWorkflowClient(unavailableBridge()).complete(item())

        assertFalse(result.ok)
        assertEquals(NativeErrorCodes.NativeInternalError, result.error?.code)
    }

    private fun unavailableBridge(): NativeCalendarCoreBridge = Proxy.newProxyInstance(
        NativeCalendarCoreBridge::class.java.classLoader,
        arrayOf(NativeCalendarCoreBridge::class.java),
    ) { proxy, method, arguments ->
        when (method.name) {
            "toString" -> "UnavailableRingNativeBridge"
            "hashCode" -> System.identityHashCode(proxy)
            "equals" -> proxy === arguments?.firstOrNull()
            "snoozeReminder", "completeEvent" -> throw UnsatisfiedLinkError("missing ${method.name}")
            else -> throw AssertionError("Unexpected bridge call: ${method.name}")
        }
    } as NativeCalendarCoreBridge

    private fun item() = RingItemRecord(
        notificationId = "11111111-1111-4111-8111-111111111111",
        deliveryId = "22222222-2222-4222-8222-222222222222",
        deliveryAttemptId = "33333333-3333-4333-8333-333333333333",
        reminderId = "44444444-4444-4444-8444-444444444444",
        eventId = "55555555-5555-4555-8555-555555555555",
        recoveryBatchId = null,
        plannedAt = "2026-08-22T00:00:00Z",
        addedAt = "2026-08-22T00:00:00Z",
        finalizeOutcome = "sent",
    )

    private fun reminder(reminderId: String): Map<String, Any?> = linkedMapOf(
        "reminder_id" to reminderId,
        "target_type" to "event",
        "target_id" to item().eventId,
        "recurrence_revision" to null,
        "occurrence_key" to null,
        "occurrence_start_at" to null,
        "template_key" to null,
        "occurrence_date" to null,
        "advance_days" to null,
        "local_time" to null,
        "timezone_mode" to null,
        "fulfillment_delivery_id" to null,
        "remind_at" to "2026-08-22T00:10:00Z",
        "advance_minutes" to null,
        "methods" to listOf("ring"),
        "message" to null,
        "is_enabled" to true,
        "status" to "pending",
        "scheduled_at" to null,
        "last_triggered_at" to null,
        "failure_reason" to null,
        "last_cancellation_reason" to null,
        "last_cancelled_at" to null,
        "expiration_reason" to null,
        "expired_at" to null,
        "reactivated_at" to null,
        "reactivation_count" to 0,
        "created_at" to "2026-08-22T00:00:00Z",
        "updated_at" to "2026-08-22T00:00:00Z",
        "deleted_at" to null,
    )
}
