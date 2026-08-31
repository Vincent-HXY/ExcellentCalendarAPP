package com.excellentcalendar.excellent_calendar.bridge.contract

import org.junit.Assert.assertThrows
import org.junit.Test

class HabitResponseInvariantTest {
    @Test
    fun dailyStatusRequiresMatchingCheckInRatioAndFinalBranch() {
        HabitContracts.dailyStatusListResponse(dailyList(daily("partial", false, 0.5, checkIn("partial"))))
        HabitContracts.dailyStatusListResponse(dailyList(daily("done", true, 1.0, checkIn("done"))))
        HabitContracts.dailyStatusListResponse(dailyList(daily("skipped", true, null, checkIn("skipped"))))

        val malformed = listOf(
            daily("partial", false, 0.5, checkIn("done")),
            daily("partial", false, null, checkIn("partial")),
            daily("partial", false, 0.0, checkIn("partial")),
            daily("partial", false, 1.0, checkIn("partial")),
            daily("done", false, 1.0, checkIn("done")),
            daily("skipped", false, null, checkIn("skipped")),
        )
        malformed.forEach { item ->
            assertThrows(NativeContractViolation::class.java) {
                HabitContracts.dailyStatusListResponse(dailyList(item))
            }
        }
    }

    @Test
    fun reminderSettingsRequiresOuterAndTemplateEnabledStateToMatch() {
        HabitContracts.checkInCommit(checkInCommit(reminderSettings(false, template(false))))

        listOf(
            reminderSettings(true, template(false), activeCount = 1),
            reminderSettings(false, template(true)),
            reminderSettings(false, template(false, deletedAt = Instant)),
        ).forEach { settings ->
            assertThrows(NativeContractViolation::class.java) {
                HabitContracts.checkInCommit(checkInCommit(settings))
            }
        }
    }

    private fun dailyList(item: Map<String, Any?>) = linkedMapOf<String, Any?>(
        "habit_id" to HabitId,
        "start_date" to Date,
        "end_date" to Date,
        "items" to listOf(item),
    )

    private fun daily(
        status: String,
        isFinal: Boolean,
        ratio: Double?,
        checkIn: Map<String, Any?>?,
    ) = linkedMapOf<String, Any?>(
        "date" to Date,
        "status" to status,
        "is_final" to isFinal,
        "check_in" to checkIn,
        "completion_ratio" to ratio,
    )

    private fun checkIn(status: String): Map<String, Any?> {
        val quantitative = status == "partial"
        return linkedMapOf(
            "id" to CheckInId,
            "habit_id" to HabitId,
            "check_date" to Date,
            "status" to status,
            "completed_count_hundredths" to if (quantitative) 100 else null,
            "target_count_snapshot_hundredths" to if (quantitative) 200 else null,
            "unit_snapshot" to if (quantitative) "page" else null,
            "completed_at" to if (status == "skipped") null else Instant,
            "note" to null,
            "source" to "manual",
            "created_at" to Instant,
            "updated_at" to Instant,
            "deleted_at" to null,
        )
    }

    private fun reminderSettings(
        enabled: Boolean,
        template: Map<String, Any?>?,
        activeCount: Int = 0,
    ) = linkedMapOf<String, Any?>(
        "is_enabled" to enabled,
        "template" to template,
        "active_reminder_count" to activeCount,
        "schedule_reconciliation_required" to false,
    )

    private fun template(enabled: Boolean, deletedAt: String? = null) = linkedMapOf<String, Any?>(
        "template_key" to TemplateId,
        "habit_id" to HabitId,
        "local_time" to "09:00",
        "timezone_mode" to "follow_device",
        "method" to "popup",
        "is_enabled" to enabled,
        "created_at" to Instant,
        "updated_at" to Instant,
        "deleted_at" to deletedAt,
    )

    private fun checkInCommit(settings: Map<String, Any?>) = linkedMapOf<String, Any?>(
        "data_saved" to true,
        "check_in" to checkIn("done"),
        "daily_status" to daily("done", true, 1.0, checkIn("done")),
        "statistics" to statistics(),
        "reminder_settings" to settings,
        "schedule_reconciliation_required" to false,
        "idempotent_replay" to false,
    )

    private fun statistics() = linkedMapOf<String, Any?>(
        "as_of_date" to Date,
        "elapsed_eligible_days" to 1,
        "done_days" to 1,
        "skipped_days" to 0,
        "partial_days" to 0,
        "missed_days" to 0,
        "current_streak" to 1,
        "longest_streak" to 1,
        "completion_rate_7_days" to 1.0,
        "completion_rate_30_days" to 1.0,
        "completion_rate_all" to 1.0,
        "quantity_progress_rate_7_days" to null,
        "quantity_progress_rate_30_days" to null,
        "quantity_progress_rate_all" to null,
        "total_completed_count_hundredths" to null,
        "average_completed_count_per_eligible_day_hundredths" to null,
    )

    private companion object {
        const val HabitId = "11111111-1111-4111-8111-111111111111"
        const val CheckInId = "33333333-3333-4333-8333-333333333333"
        const val TemplateId = "44444444-4444-4444-8444-444444444444"
        const val Date = "2026-08-28"
        const val Instant = "2026-08-28T01:00:00Z"
    }
}
