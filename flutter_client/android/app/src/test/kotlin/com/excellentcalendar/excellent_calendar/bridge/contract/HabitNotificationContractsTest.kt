package com.excellentcalendar.excellent_calendar.bridge.contract

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertNull
import org.junit.Test

class HabitNotificationContractsTest {
    @Test
    fun preparedHabitDeliveryRequiresMatchingCppActionIdentity() {
        val parsed = V2PreparedDelivery.fromData(
            linkedMapOf(
                "notification" to notification("prepared"),
                "tap_payload" to tapPayload(),
                "habit_action_payload" to actionPayload(),
                "idempotent_replay" to false,
            ),
        )
        assertEquals(ActionId, parsed.habitActionPayload?.get("action_id"))
        assertEquals("habit.detail", parsed.tapPayload["route"])

        assertThrows(NativeContractViolation::class.java) {
            V2PreparedDelivery.fromData(
                linkedMapOf(
                    "notification" to notification("prepared"),
                    "tap_payload" to tapPayload(),
                    "idempotent_replay" to false,
                ),
            )
        }
    }

    @Test
    fun habitReminderAcceptsOnlyTheDateOccurrenceBranch() {
        ReminderV2Contracts.response(reminder())
        val mixed = LinkedHashMap(reminder()).apply { this["advance_days"] = 0 }
        assertThrows(NativeContractViolation::class.java) { ReminderV2Contracts.response(mixed) }
    }

    @Test
    fun habitTapPreservesOccurrenceIdentityAndRoute() {
        val normalized = NotificationTapPayloadContract.normalize(tapPayload(), "2026-08-28T02:00:00Z")
        assertEquals(HabitId, normalized["target_id"])
        assertEquals(OccurrenceId, normalized["occurrence_key"])
        assertEquals("habit.detail", normalized["route"])
        assertEquals("2026-08-28T02:00:00Z", normalized["opened_at"])
    }

    @Test
    fun habitPreparedAttemptCanBeAbandonedWithoutRecoveryBatch() {
        val abandoned = notification("abandoned").toMutableMap().apply {
            this["abandon_reason"] = "habit_occurrence_elapsed"
            this["finalized_at"] = "2026-08-29T00:00:00Z"
            this["updated_at"] = "2026-08-29T00:00:00Z"
        }
        val data = linkedMapOf(
            "notification" to abandoned,
            "tap_payload" to tapPayload(),
            "habit_action_payload" to actionPayload(),
            "idempotent_replay" to true,
        )
        val parsed = V2PreparedDelivery.fromData(data)
        assertNull(parsed.notification["resolved_by_recovery_batch_id"])
    }

    companion object {
        private const val NotificationId = "11111111-1111-4111-8111-111111111111"
        private const val DeliveryId = "22222222-2222-4222-8222-222222222222"
        private const val AttemptId = "33333333-3333-4333-8333-333333333333"
        private const val ReminderId = "44444444-4444-4444-8444-444444444444"
        private const val HabitId = "55555555-5555-4555-8555-555555555555"
        private const val OccurrenceId = "66666666-6666-4666-8666-666666666666"
        private const val TemplateId = "77777777-7777-4777-8777-777777777777"
        private const val ActionId = "88888888-8888-4888-8888-888888888888"
        private const val At = "2026-08-28T01:00:00Z"

        private fun notification(status: String) = linkedMapOf<String, Any?>(
            "notification_id" to NotificationId, "delivery_id" to DeliveryId, "delivery_attempt_id" to AttemptId,
            "kind" to "reminder", "reminder_id" to ReminderId, "recovery_batch_id" to null,
            "resolved_by_recovery_batch_id" to null, "target_type" to "habit", "target_id" to HabitId,
            "occurrence_key" to OccurrenceId, "covered_reminder_ids" to emptyList<String>(), "method" to "popup",
            "title" to "Read", "body" to "Complete today's challenge", "planned_at" to At, "status" to status,
            "failure_class" to null, "error_code" to null, "abandon_reason" to null, "prepared_at" to At,
            "finalized_at" to null, "sent_at" to null, "created_at" to At, "updated_at" to At,
        )
        private fun tapPayload() = linkedMapOf<String, Any?>(
            "notification_id" to NotificationId, "delivery_id" to DeliveryId, "delivery_attempt_id" to AttemptId,
            "kind" to "reminder", "reminder_id" to ReminderId, "recovery_batch_id" to null,
            "target_type" to "habit", "target_id" to HabitId, "occurrence_key" to OccurrenceId, "route" to "habit.detail",
        )
        private fun actionPayload() = linkedMapOf<String, Any?>(
            "action_id" to ActionId, "action_type" to "complete", "habit_id" to HabitId, "check_date" to "2026-08-28",
            "occurrence_key" to OccurrenceId, "reminder_id" to ReminderId, "delivery_id" to DeliveryId,
        )
        private fun reminder() = linkedMapOf<String, Any?>(
            "reminder_id" to ReminderId, "target_type" to "habit", "target_id" to HabitId,
            "recurrence_revision" to null, "occurrence_key" to OccurrenceId, "occurrence_start_at" to null,
            "template_key" to TemplateId, "occurrence_date" to "2026-08-28", "advance_days" to null,
            "local_time" to "09:00", "timezone_mode" to "follow_device", "fulfillment_delivery_id" to null,
            "remind_at" to At, "advance_minutes" to null, "methods" to listOf("popup"), "message" to null,
            "is_enabled" to true, "status" to "pending", "scheduled_at" to null, "last_triggered_at" to null,
            "failure_reason" to null, "last_cancellation_reason" to null, "last_cancelled_at" to null,
            "expiration_reason" to null, "expired_at" to null, "reactivated_at" to null, "reactivation_count" to 0,
            "created_at" to At, "updated_at" to At, "deleted_at" to null,
        )
    }
}
