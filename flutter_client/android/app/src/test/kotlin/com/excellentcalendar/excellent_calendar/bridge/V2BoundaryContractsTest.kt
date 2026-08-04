package com.excellentcalendar.excellent_calendar.bridge

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeContractViolation
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.NotificationTapPayloadContract
import com.excellentcalendar.excellent_calendar.bridge.contract.V2FinalizeDelivery
import com.excellentcalendar.excellent_calendar.bridge.contract.V2RecoveryPlan
import com.excellentcalendar.excellent_calendar.bridge.contract.V2RequestContracts
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class V2BoundaryContractsTest {
    @Test
    fun nativeResultV2RequiresExactContractVersion() {
        val v2 = NativeContractJsonCodec.encodeObject(
            linkedMapOf("ok" to true, "data" to emptyMap<String, Any?>(), "error" to null, "contract_version" to 2, "request_id" to "request"),
        )
        assertEquals(2, NativeResultContract.fromJson(v2, 2) { }.contractVersion)

        val v1 = NativeContractJsonCodec.encodeObject(
            linkedMapOf("ok" to true, "data" to emptyMap<String, Any?>(), "error" to null, "contract_version" to 1, "request_id" to "request"),
        )
        assertThrows(NativeContractViolation::class.java) { NativeResultContract.fromJson(v1, 2) { } }

        val missing = NativeContractJsonCodec.encodeObject(
            linkedMapOf("ok" to true, "data" to emptyMap<String, Any?>(), "error" to null, "contract_version" to null, "request_id" to "request"),
        )
        assertThrows(NativeContractViolation::class.java) { NativeResultContract.fromJson(missing, 2) { } }
    }

    @Test
    fun nativeResultV2RejectsAdditionalProperties() {
        val malformed = NativeContractJsonCodec.encodeObject(
            linkedMapOf(
                "ok" to true,
                "data" to emptyMap<String, Any?>(),
                "error" to null,
                "contract_version" to 2,
                "request_id" to "request",
                "unexpected" to true,
            ),
        )

        assertThrows(NativeContractViolation::class.java) {
            NativeResultContract.fromJson(malformed, 2) { }
        }
    }

    @Test
    fun nativeResultV2AcceptsAllSecureTokenErrorsAndRejectsUnknownErrorFields() {
        listOf(
            NativeErrorCodes.SecureTokenNotFound,
            NativeErrorCodes.SecureTokenStorageFailed,
            NativeErrorCodes.SecureTokenCorrupted,
        ).forEach { code ->
            val failure = NativeResultContract.failure(code, "secure storage failed", contractVersion = 2).toMap()
            assertEquals(code, NativeResultContract.fromMap(failure, 2) { }.error?.code)
        }

        val malformedError = NativeResultContract.failure(
            NativeErrorCodes.SecureTokenCorrupted,
            "secure storage failed",
            contractVersion = 2,
        ).toMap().toMutableMap()
        @Suppress("UNCHECKED_CAST")
        malformedError["error"] = (malformedError["error"] as Map<String, Any?>) + ("unexpected" to true)
        assertThrows(NativeContractViolation::class.java) {
            NativeResultContract.fromMap(malformedError, 2) { }
        }
    }

    @Test
    fun createEventEnforcesTimedAndAllDayAtomicShapes() {
        val timed = validTimedCreate()
        V2RequestContracts.createEvent(timed)

        assertThrows(NativeContractViolation::class.java) {
            V2RequestContracts.createEvent(timed + ("start_date" to "2026-03-29"))
        }

        val allDay = timed + mapOf(
            "start_at" to null,
            "end_at" to null,
            "start_date" to "2026-03-29",
            "end_date" to "2026-03-30",
            "is_all_day" to true,
        )
        V2RequestContracts.createEvent(allDay)
    }

    @Test
    fun recurrenceRejectsDerivedFieldsAndAllDayReminderCombination() {
        val recurrence = linkedMapOf<String, Any?>(
            "frequency" to "monthly",
            "interval" to 1,
            "end_at" to null,
            "count" to null,
            "day_of_month" to 31,
        )
        assertThrows(NativeContractViolation::class.java) {
            V2RequestContracts.createEvent(validTimedCreate() + ("recurrence" to recurrence))
        }

        recurrence.remove("day_of_month")
        val allDayRecurring = validTimedCreate() + mapOf(
            "start_at" to null,
            "end_at" to null,
            "start_date" to "2026-01-31",
            "end_date" to "2026-02-01",
            "is_all_day" to true,
            "recurrence" to recurrence,
            "reminders" to listOf(
                mapOf(
                    "target_type" to "event",
                    "advance_minutes" to 30,
                    "methods" to listOf("popup"),
                    "message" to null,
                    "is_enabled" to true,
                    "source" to "manual",
                ),
            ),
        )
        assertThrows(NativeContractViolation::class.java) { V2RequestContracts.createEvent(allDayRecurring) }
    }

    @Test
    fun embeddedOrdinaryReminderRejectsInvalidTypesAndEnums() {
        val reminder = linkedMapOf<String, Any?>(
            "target_type" to "event",
            "target_id" to null,
            "remind_at" to "2026-03-29T00:30:00Z",
            "advance_minutes" to null,
            "methods" to listOf("popup"),
            "message" to null,
            "is_enabled" to true,
            "source" to "manual",
        )

        assertThrows(NativeContractViolation::class.java) {
            V2RequestContracts.createEvent(validTimedCreate() + ("reminders" to listOf(reminder + ("target_type" to "habit"))))
        }
        assertThrows(NativeContractViolation::class.java) {
            V2RequestContracts.createEvent(validTimedCreate() + ("reminders" to listOf(reminder + ("methods" to listOf("unknown")))))
        }
        assertThrows(NativeContractViolation::class.java) {
            V2RequestContracts.createEvent(validTimedCreate() + ("reminders" to listOf(reminder + ("is_enabled" to "true"))))
        }
        assertThrows(NativeContractViolation::class.java) {
            V2RequestContracts.createEvent(validTimedCreate() + ("reminders" to listOf(reminder + ("source" to "unknown"))))
        }
    }

    @Test
    fun listRemindersAcceptsExpiredStatusAndRejectsUnknownStatus() {
        val request = V2RequestContracts.listReminders(mapOf("status" to listOf("expired")))

        assertEquals(listOf("expired"), request.value["status"])
        assertThrows(NativeContractViolation::class.java) {
            V2RequestContracts.listReminders(mapOf("status" to listOf("unknown")))
        }
    }

    @Test
    fun adoptedAttemptFinalizeUsesResolvedRecoveryIdentity() {
        val response = linkedMapOf<String, Any?>(
            "notification" to validNotification() + mapOf("resolved_by_recovery_batch_id" to "batch"),
            "reminder" to validReminder(),
            "successor" to null,
            "recovery_batch" to validRecoveryBatch(),
            "idempotent_replay" to false,
        )

        val finalized = V2FinalizeDelivery.fromData(response)
        assertEquals("batch", finalized.notification["resolved_by_recovery_batch_id"])
        assertEquals("batch", finalized.recoveryBatch?.get("recovery_batch_id"))

        assertThrows(NativeContractViolation::class.java) {
            V2FinalizeDelivery.fromData(response + ("recovery_batch" to null))
        }
    }

    @Test
    fun recoveryResolutionRequiresCompleteIdentity() {
        val malformed = linkedMapOf<String, Any?>(
            "batch" to validRecoveryBatch(),
            "detail_reminders" to emptyList<Any?>(),
            "prepared_attempt_resolutions" to listOf(
                mapOf("delivery_id" to "delivery", "resolution" to "adopted_detail"),
            ),
            "idempotent_replay" to false,
        )

        assertThrows(NativeContractViolation::class.java) { V2RecoveryPlan.fromData(malformed) }

        val invalidConditional = malformed + (
            "prepared_attempt_resolutions" to listOf(
                mapOf(
                    "delivery_attempt_id" to "attempt",
                    "delivery_id" to "delivery",
                    "reminder_id" to "reminder",
                    "resolution" to "adopted_detail",
                    "replacement_delivery_id" to "replacement",
                ),
            )
            )
        assertThrows(NativeContractViolation::class.java) { V2RecoveryPlan.fromData(invalidConditional) }
    }

    @Test
    fun occurrenceIdentityRequiresRevisionKeyAndExactlyOnePlannedStart() {
        val valid = linkedMapOf<String, Any?>(
            "event_id" to "event",
            "recurrence_revision" to 3,
            "occurrence_key" to "occurrence",
            "occurrence_start_at" to "2026-10-25T00:30:00Z",
            "occurrence_start_date" to null,
        )
        V2RequestContracts.occurrenceOperation(valid)
        assertThrows(NativeContractViolation::class.java) {
            V2RequestContracts.occurrenceOperation(valid + ("occurrence_start_date" to "2026-10-25"))
        }
        assertThrows(NativeContractViolation::class.java) {
            V2RequestContracts.occurrenceOperation(valid + ("recurrence_revision" to 0))
        }
    }

    @Test
    fun v2TapPayloadAddsOpenedAtOnlyOnActualTap() {
        val prepared = linkedMapOf<String, Any?>(
            "notification_id" to "notification",
            "delivery_id" to "delivery",
            "delivery_attempt_id" to "attempt",
            "kind" to "reminder",
            "reminder_id" to "reminder",
            "recovery_batch_id" to null,
            "target_type" to "event",
            "target_id" to "event",
            "occurrence_key" to "occurrence",
            "route" to "/event/detail",
        )
        assertNull(prepared["opened_at"])
        val opened = NotificationTapPayloadContract.normalize(prepared, "2026-08-04T00:00:00Z")
        assertEquals("2026-08-04T00:00:00Z", opened["opened_at"])
        assertEquals("delivery", opened["delivery_id"])
    }

    private fun validTimedCreate(): Map<String, Any?> = linkedMapOf(
        "title" to "Meeting",
        "start_at" to "2026-03-29T01:00:00Z",
        "end_at" to "2026-03-29T02:00:00Z",
        "start_date" to null,
        "end_date" to null,
        "is_all_day" to false,
        "timezone" to "Europe/London",
        "source" to "manual",
    )

    private fun validRecoveryBatch(): Map<String, Any?> = linkedMapOf(
        "recovery_batch_id" to "batch",
        "recovery_request_id" to "request",
        "trigger_source" to "alarm_reconcile",
        "started_at" to "2026-08-04T00:00:00Z",
        "window_start_at" to "2026-08-01T00:00:00Z",
        "detail_reminder_ids" to emptyList<String>(),
        "summary_reminder_ids" to emptyList<String>(),
        "older_skipped_occurrence_count" to 0,
        "older_skipped_reminder_count" to 0,
        "window_overflow_count" to 0,
        "summary_delivery_id" to null,
        "status" to "in_progress",
        "completed_at" to null,
    )

    private fun validNotification(): Map<String, Any?> = linkedMapOf(
        "notification_id" to "notification",
        "delivery_id" to "delivery",
        "delivery_attempt_id" to "attempt",
        "kind" to "reminder",
        "reminder_id" to "reminder",
        "recovery_batch_id" to null,
        "resolved_by_recovery_batch_id" to null,
        "target_type" to "event",
        "target_id" to "event",
        "occurrence_key" to null,
        "method" to "popup",
        "title" to "Title",
        "body" to "Body",
        "planned_at" to "2026-08-04T01:00:00Z",
        "status" to "sent",
        "failure_class" to null,
        "error_code" to null,
        "abandon_reason" to null,
        "prepared_at" to "2026-08-04T00:00:00Z",
        "finalized_at" to "2026-08-04T00:00:01Z",
        "sent_at" to "2026-08-04T00:00:01Z",
        "created_at" to "2026-08-04T00:00:00Z",
        "updated_at" to "2026-08-04T00:00:01Z",
    )

    private fun validReminder(): Map<String, Any?> = linkedMapOf(
        "reminder_id" to "reminder",
        "target_type" to "event",
        "target_id" to "event",
        "recurrence_revision" to null,
        "occurrence_key" to null,
        "occurrence_start_at" to null,
        "remind_at" to "2026-08-04T01:00:00Z",
        "advance_minutes" to null,
        "methods" to listOf("popup"),
        "message" to null,
        "is_enabled" to false,
        "status" to "sent",
        "scheduled_at" to null,
        "last_triggered_at" to "2026-08-04T00:00:01Z",
        "failure_reason" to null,
        "last_cancellation_reason" to null,
        "last_cancelled_at" to null,
        "expiration_reason" to null,
        "expired_at" to null,
        "reactivated_at" to null,
        "reactivation_count" to 0,
        "created_at" to "2026-08-04T00:00:00Z",
        "updated_at" to "2026-08-04T00:00:01Z",
        "deleted_at" to null,
    )
}
