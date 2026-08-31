package com.excellentcalendar.excellent_calendar.bridge.contract

import java.time.DateTimeException
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.ResolverStyle
import java.time.temporal.ChronoUnit
import java.util.UUID

/** Strict Habit V1 MethodChannel requests and C++ projections. */
internal object HabitContracts {
    private const val MaxSafeInteger = 9_007_199_254_740_991L
    private val utcSecond = Regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
    private val localTime = Regex("^(?:[01][0-9]|2[0-3]):[0-5][0-9]$")
    private val dateFormatter = DateTimeFormatter.ISO_LOCAL_DATE.withResolverStyle(ResolverStyle.STRICT)

    fun create(arguments: Any?): V2JsonRequest = request(arguments, "CreateHabitRequest") { map ->
        exact(map, setOf("title", "description", "category_id", "recurrence", "target_count_hundredths", "unit", "start_date", "end_date", "reminder", "timezone"), "CreateHabitRequest")
        habitDraft(map, "CreateHabitRequest", includeRecurrence = true, reminderRequired = true)
    }

    fun update(arguments: Any?): V2JsonRequest = request(arguments, "UpdateHabitRequest") { map ->
        val required = setOf("id", "expected_updated_at", "title", "description", "category_id", "target_count_hundredths", "unit", "start_date", "end_date", "timezone")
        allowedAndRequired(map, required + "reminder", required, "UpdateHabitRequest")
        uuid(map, "id", "UpdateHabitRequest")
        utc(map, "expected_updated_at", "UpdateHabitRequest")
        habitDraft(map, "UpdateHabitRequest", includeRecurrence = false, reminderRequired = false)
    }

    fun list(arguments: Any?): V2JsonRequest = request(arguments, "ListHabitsRequest") { map ->
        allowedAndRequired(map, setOf("timezone", "lifecycle_statuses", "category_ids", "pagination"), setOf("timezone"), "ListHabitsRequest")
        timezone(map, "timezone", "ListHabitsRequest")
        stringArray(map, "lifecycle_statuses", "ListHabitsRequest", 1, 4, setOf("upcoming", "active", "completed", "ended_early"))
        stringArray(map, "category_ids", "ListHabitsRequest", 1, 100, maximumCodePoints = 512)
        map["pagination"]?.let { paginationRequest(objectMap(it, "ListHabitsRequest.pagination")) }
    }

    fun detail(arguments: Any?): V2JsonRequest = request(arguments, "GetHabitDetailRequest") { map ->
        exact(map, setOf("id", "timezone", "history_page_size"), "GetHabitDetailRequest")
        uuid(map, "id", "GetHabitDetailRequest")
        timezone(map, "timezone", "GetHabitDetailRequest")
        integer(map, "history_page_size", "GetHabitDetailRequest", 1, 120)
    }

    fun end(arguments: Any?): V2JsonRequest = optimisticIdRequest(arguments, "EndHabitRequest")
    fun delete(arguments: Any?): V2JsonRequest = optimisticIdRequest(arguments, "DeleteHabitRequest")

    fun checkIn(arguments: Any?): V2JsonRequest = request(arguments, "HabitCheckInRequest") { map ->
        exact(map, setOf("habit_id", "check_date", "status", "completed_count_hundredths", "note", "timezone"), "HabitCheckInRequest")
        checkInFields(map, "HabitCheckInRequest", internal = false)
    }

    fun manualCheckInCommand(arguments: Any?): V2JsonRequest {
        val public = checkIn(arguments).value
        return V2JsonRequest(LinkedHashMap(public).apply {
            this["source"] = "manual"
            this["occurrence_key"] = null
            this["action_id"] = null
        })
    }

    fun notificationActionCommand(payload: Map<String, Any?>, timezone: String): V2JsonRequest {
        actionPayload(payload)
        val command = linkedMapOf<String, Any?>(
            "habit_id" to payload["habit_id"],
            "check_date" to payload["check_date"],
            "status" to "done",
            "completed_count_hundredths" to null,
            "note" to null,
            "source" to "notification_action",
            "occurrence_key" to payload["occurrence_key"],
            "action_id" to payload["action_id"],
            "timezone" to timezone,
        )
        checkInFields(command, "HabitCheckInCommandRequest", internal = true)
        return V2JsonRequest(command)
    }

    fun clearCheckIn(arguments: Any?): V2JsonRequest = request(arguments, "ClearHabitCheckInRequest") { map ->
        exact(map, setOf("habit_id", "check_date", "timezone"), "ClearHabitCheckInRequest")
        uuid(map, "habit_id", "ClearHabitCheckInRequest")
        date(map, "check_date", "ClearHabitCheckInRequest")
        timezone(map, "timezone", "ClearHabitCheckInRequest")
    }

    fun listDailyStatuses(arguments: Any?): V2JsonRequest = request(arguments, "ListHabitDailyStatusesRequest") { map ->
        exact(map, setOf("habit_id", "start_date", "end_date", "timezone"), "ListHabitDailyStatusesRequest")
        uuid(map, "habit_id", "ListHabitDailyStatusesRequest")
        val start = date(map, "start_date", "ListHabitDailyStatusesRequest")
        val end = date(map, "end_date", "ListHabitDailyStatusesRequest")
        validateDateRange(start, end, "ListHabitDailyStatusesRequest")
        timezone(map, "timezone", "ListHabitDailyStatusesRequest")
    }

    fun setReminder(arguments: Any?): V2JsonRequest = request(arguments, "SetHabitReminderRequest") { map ->
        exact(map, setOf("habit_id", "expected_updated_at", "reminder", "timezone"), "SetHabitReminderRequest")
        uuid(map, "habit_id", "SetHabitReminderRequest")
        utc(map, "expected_updated_at", "SetHabitReminderRequest")
        reminderPlan(objectMap(map["reminder"], "SetHabitReminderRequest.reminder"), "SetHabitReminderRequest.reminder")
        timezone(map, "timezone", "SetHabitReminderRequest")
    }

    fun reconcileRequest(timezone: String, trigger: String, cursor: String?, limit: Int): V2JsonRequest {
        val map = linkedMapOf<String, Any?>("timezone" to timezone, "trigger_source" to trigger, "cursor" to cursor, "limit" to limit)
        exact(map, setOf("timezone", "trigger_source", "cursor", "limit"), "ReconcileHabitRemindersRequest")
        timezone(map, "timezone", "ReconcileHabitRemindersRequest")
        enum(map, "trigger_source", "ReconcileHabitRemindersRequest", setOf("app_start", "device_boot", "app_update", "date_changed", "time_changed", "timezone_changed", "permission_restored", "manual_retry"))
        nullableBoundedString(map, "cursor", "ReconcileHabitRemindersRequest", 1, 512)
        integer(map, "limit", "ReconcileHabitRemindersRequest", 1, 100)
        return V2JsonRequest(map)
    }

    fun mutationCommit(data: Any?) {
        val map = objectMap(data, "HabitMutationCommitResponse")
        exact(map, setOf("data_saved", "detail", "schedule_reconciliation_required"), "HabitMutationCommitResponse")
        trueValue(map, "data_saved", "HabitMutationCommitResponse")
        detailResponse(map["detail"])
        boolean(map, "schedule_reconciliation_required", "HabitMutationCommitResponse")
    }

    fun deleteCommit(data: Any?) {
        val map = objectMap(data, "HabitDeleteCommitResponse")
        exact(map, setOf("data_saved", "habit_id", "deleted_at", "schedule_reconciliation_required"), "HabitDeleteCommitResponse")
        trueValue(map, "data_saved", "HabitDeleteCommitResponse")
        uuid(map, "habit_id", "HabitDeleteCommitResponse")
        utc(map, "deleted_at", "HabitDeleteCommitResponse")
        boolean(map, "schedule_reconciliation_required", "HabitDeleteCommitResponse")
    }

    fun checkInCommit(data: Any?) {
        val map = objectMap(data, "HabitCheckInCommitResponse")
        exact(map, setOf("data_saved", "check_in", "daily_status", "statistics", "reminder_settings", "schedule_reconciliation_required", "idempotent_replay"), "HabitCheckInCommitResponse")
        trueValue(map, "data_saved", "HabitCheckInCommitResponse")
        map["check_in"]?.let(::checkInResponse)
        dailyStatusResponse(map["daily_status"])
        statisticsResponse(map["statistics"])
        reminderSettingsResponse(map["reminder_settings"])
        boolean(map, "schedule_reconciliation_required", "HabitCheckInCommitResponse")
        boolean(map, "idempotent_replay", "HabitCheckInCommitResponse")
    }

    fun listResponse(data: Any?) {
        val map = objectMap(data, "HabitListResponse")
        exact(map, setOf("items", "pagination", "today_progress"), "HabitListResponse")
        objectArray(map["items"], "HabitListResponse.items", 100).forEach(::summaryResponse)
        paginationResponse(objectMap(map["pagination"], "HabitListResponse.pagination"))
        todayProgressResponse(map["today_progress"])
    }

    fun detailResponse(data: Any?) {
        val map = objectMap(data, "HabitDetailResponse")
        exact(map, setOf("habit", "recurrence", "lifecycle_status", "statistics", "reminder_settings", "today", "history", "history_start_date", "history_end_date", "has_earlier_history", "has_ever_checked_in", "latest_check_in_date", "challenge_time_progress", "remaining_days"), "HabitDetailResponse")
        habitResponse(map["habit"])
        recurrenceResponse(map["recurrence"])
        enum(map, "lifecycle_status", "HabitDetailResponse", setOf("upcoming", "active", "completed", "ended_early"))
        statisticsResponse(map["statistics"])
        reminderSettingsResponse(map["reminder_settings"])
        map["today"]?.let(::dailyStatusResponse)
        val history = objectArray(map["history"], "HabitDetailResponse.history", 120)
        history.forEach(::dailyStatusResponse)
        nullableDate(map, "history_start_date", "HabitDetailResponse")
        nullableDate(map, "history_end_date", "HabitDetailResponse")
        boolean(map, "has_earlier_history", "HabitDetailResponse")
        boolean(map, "has_ever_checked_in", "HabitDetailResponse")
        nullableDate(map, "latest_check_in_date", "HabitDetailResponse")
        ratio(map, "challenge_time_progress", "HabitDetailResponse")
        integer(map, "remaining_days", "HabitDetailResponse", 0, Int.MAX_VALUE)
        if (history.isEmpty() && (map["history_start_date"] != null || map["history_end_date"] != null || map["has_earlier_history"] != false)) violation("HabitDetailResponse empty history is inconsistent.", "HabitDetailResponse.history")
        if (history.isNotEmpty()) {
            val dates = history.mapIndexed { index, item -> date(item, "date", "HabitDetailResponse.history[$index]") }
            if (dates.zipWithNext().any { (current, next) -> !current.isAfter(next) }) violation("HabitDetailResponse history must be strictly date-descending.", "HabitDetailResponse.history")
            if (map["history_start_date"] != dates.last().toString() || map["history_end_date"] != dates.first().toString()) violation("HabitDetailResponse history bounds do not match its items.", "HabitDetailResponse.history")
        }
        if ((map["has_ever_checked_in"] == true) != (map["latest_check_in_date"] != null)) violation("HabitDetailResponse check-in lock fields are inconsistent.", "HabitDetailResponse.latest_check_in_date")
        if (map["lifecycle_status"] == "upcoming" && map["today"] != null) violation("Upcoming Habit must not expose today.", "HabitDetailResponse.today")
        if (map["lifecycle_status"] == "active" && map["today"] == null) violation("Active Habit must expose today.", "HabitDetailResponse.today")
    }

    fun dailyStatusListResponse(data: Any?) {
        val map = objectMap(data, "HabitDailyStatusListResponse")
        exact(map, setOf("habit_id", "start_date", "end_date", "items"), "HabitDailyStatusListResponse")
        uuid(map, "habit_id", "HabitDailyStatusListResponse")
        val start = date(map, "start_date", "HabitDailyStatusListResponse")
        val end = date(map, "end_date", "HabitDailyStatusListResponse")
        validateDateRange(start, end, "HabitDailyStatusListResponse")
        val items = objectArray(map["items"], "HabitDailyStatusListResponse.items", 400)
        items.forEach(::dailyStatusResponse)
        val expectedCount = ChronoUnit.DAYS.between(start, end).toInt() + 1
        if (items.size != expectedCount) violation("Daily status items must cover the inclusive requested range.", "HabitDailyStatusListResponse.items")
        items.forEachIndexed { index, item ->
            if (item["date"] != start.plusDays(index.toLong()).toString()) violation("Daily status items must be contiguous and date-ascending.", "HabitDailyStatusListResponse.items[$index].date")
        }
    }

    fun reconcileResponse(data: Any?, expectedLimit: Int? = null): HabitReconcilePage {
        val map = objectMap(data, "ReconcileHabitRemindersResponse")
        exact(map, setOf("request_limit", "processed_count", "materialized_count", "expired_count", "cancelled_count", "unchanged_count", "schedule_reconciliation_required", "has_more", "next_cursor"), "ReconcileHabitRemindersResponse")
        val limit = integer(map, "request_limit", "ReconcileHabitRemindersResponse", 1, 100).toInt()
        if (expectedLimit != null && limit != expectedLimit) violation("request_limit does not echo the request.", "ReconcileHabitRemindersResponse.request_limit")
        val processed = integer(map, "processed_count", "ReconcileHabitRemindersResponse", 0, 100).toInt()
        val outcomes = listOf("materialized_count", "expired_count", "cancelled_count", "unchanged_count").sumOf { integer(map, it, "ReconcileHabitRemindersResponse", 0, 100) }
        if (processed.toLong() != outcomes || processed > limit) violation("Reconciliation outcome counts are inconsistent.", "ReconcileHabitRemindersResponse.processed_count")
        boolean(map, "schedule_reconciliation_required", "ReconcileHabitRemindersResponse")
        val hasMore = boolean(map, "has_more", "ReconcileHabitRemindersResponse")
        nullableBoundedString(map, "next_cursor", "ReconcileHabitRemindersResponse", 1, 512)
        val cursor = map["next_cursor"] as String?
        if (hasMore && (processed == 0 || cursor == null)) violation("A continuation must make progress and carry a cursor.", "ReconcileHabitRemindersResponse.next_cursor")
        if (!hasMore && cursor != null) violation("A completed reconciliation must not carry a cursor.", "ReconcileHabitRemindersResponse.next_cursor")
        return HabitReconcilePage(processed, map["schedule_reconciliation_required"] as Boolean, hasMore, cursor)
    }

    fun actionPayload(data: Any?): Map<String, Any?> {
        val map = objectMap(data, "HabitNotificationActionPayload")
        exact(map, setOf("action_id", "action_type", "habit_id", "check_date", "occurrence_key", "reminder_id", "delivery_id"), "HabitNotificationActionPayload")
        listOf("action_id", "habit_id", "occurrence_key", "reminder_id", "delivery_id").forEach { uuid(map, it, "HabitNotificationActionPayload") }
        if (map["action_type"] != "complete") violation("Habit action_type must be complete.", "HabitNotificationActionPayload.action_type")
        date(map, "check_date", "HabitNotificationActionPayload")
        return map
    }

    private fun optimisticIdRequest(arguments: Any?, parent: String): V2JsonRequest = request(arguments, parent) { map ->
        exact(map, setOf("id", "expected_updated_at", "timezone"), parent)
        uuid(map, "id", parent)
        utc(map, "expected_updated_at", parent)
        timezone(map, "timezone", parent)
    }

    private fun habitDraft(map: Map<String, Any?>, parent: String, includeRecurrence: Boolean, reminderRequired: Boolean) {
        boundedString(map, "title", parent, 1, 80)
        nullableBoundedString(map, "description", parent, 0, 2000)
        nullableString(map, "category_id", parent)
        if (includeRecurrence) recurrenceInput(objectMap(map["recurrence"], "$parent.recurrence"), "$parent.recurrence")
        pairedQuantity(map, parent)
        val start = date(map, "start_date", parent)
        val end = date(map, "end_date", parent)
        validateDateRange(start, end, parent)
        if (reminderRequired || map.containsKey("reminder")) reminderPlan(objectMap(map["reminder"], "$parent.reminder"), "$parent.reminder")
        timezone(map, "timezone", parent)
    }

    private fun recurrenceInput(map: Map<String, Any?>, parent: String) {
        exact(map, setOf("frequency", "interval", "timezone_mode"), parent)
        if (map["frequency"] != "daily" || integer(map, "interval", parent, 1, 1) != 1L || map["timezone_mode"] != "follow_device") violation("Habit recurrence must be daily/1/follow_device.", parent)
    }

    private fun reminderPlan(map: Map<String, Any?>, parent: String) {
        exact(map, setOf("is_enabled", "local_time", "timezone_mode", "method"), parent)
        val enabled = boolean(map, "is_enabled", parent)
        nullableString(map, "local_time", parent)
        if (map["timezone_mode"] != "follow_device" || map["method"] != "popup") violation("Habit reminder supports follow_device popup only.", parent)
        val time = map["local_time"]
        if ((enabled && (time !is String || !localTime.matches(time))) || (!enabled && time != null)) violation("Habit reminder local_time does not match enabled state.", "$parent.local_time")
    }

    private fun checkInFields(map: Map<String, Any?>, parent: String, internal: Boolean) {
        if (internal) exact(map, setOf("habit_id", "check_date", "status", "completed_count_hundredths", "note", "source", "occurrence_key", "action_id", "timezone"), parent)
        uuid(map, "habit_id", parent)
        date(map, "check_date", parent)
        val status = enum(map, "status", parent, setOf("done", "partial", "skipped"))
        nullableSafeInteger(map, "completed_count_hundredths", parent, 1)
        nullableBoundedString(map, "note", parent, 0, 500)
        timezone(map, "timezone", parent)
        if (status == "partial" && map["completed_count_hundredths"] == null) violation("Partial requires completed_count_hundredths.", "$parent.completed_count_hundredths")
        if (status == "skipped" && map["completed_count_hundredths"] != null) violation("Skipped forbids completed_count_hundredths.", "$parent.completed_count_hundredths")
        if (internal) {
            val source = enum(map, "source", parent, setOf("manual", "notification_action"))
            nullableUuid(map, "occurrence_key", parent)
            nullableUuid(map, "action_id", parent)
            val action = source == "notification_action"
            if (action != (map["occurrence_key"] != null && map["action_id"] != null) || action && (status != "done" || map["completed_count_hundredths"] != null || map["note"] != null)) violation("Habit check-in source identity is inconsistent.", "$parent.source")
        }
    }

    private fun habitResponse(data: Any?) {
        val map = objectMap(data, "HabitResponse")
        exact(map, setOf("id", "title", "description", "category_id", "recurrence_id", "target_count_hundredths", "unit", "start_date", "end_date", "ended_date", "is_active", "created_at", "updated_at", "deleted_at"), "HabitResponse")
        uuid(map, "id", "HabitResponse"); uuid(map, "recurrence_id", "HabitResponse")
        boundedString(map, "title", "HabitResponse", 1, 80); nullableBoundedString(map, "description", "HabitResponse", 0, 2000); nullableString(map, "category_id", "HabitResponse")
        pairedQuantity(map, "HabitResponse")
        date(map, "start_date", "HabitResponse"); date(map, "end_date", "HabitResponse"); nullableDate(map, "ended_date", "HabitResponse")
        val active = boolean(map, "is_active", "HabitResponse")
        utc(map, "created_at", "HabitResponse"); utc(map, "updated_at", "HabitResponse"); nullableUtc(map, "deleted_at", "HabitResponse")
        if (active && map["ended_date"] != null) violation("Active Habit must not have ended_date.", "HabitResponse.ended_date")
        if (!active && map["deleted_at"] == null && map["ended_date"] == null) violation("Ended Habit requires ended_date.", "HabitResponse.ended_date")
    }

    private fun recurrenceResponse(data: Any?) {
        val map = objectMap(data, "HabitRecurrenceResponse")
        exact(map, setOf("id", "frequency", "interval", "timezone_mode", "created_at", "updated_at", "deleted_at"), "HabitRecurrenceResponse")
        uuid(map, "id", "HabitRecurrenceResponse")
        if (map["frequency"] != "daily" || integer(map, "interval", "HabitRecurrenceResponse", 1, 1) != 1L || map["timezone_mode"] != "follow_device" || map["deleted_at"] != null) violation("Habit recurrence projection is invalid.", "HabitRecurrenceResponse")
        utc(map, "created_at", "HabitRecurrenceResponse"); utc(map, "updated_at", "HabitRecurrenceResponse")
    }

    private fun summaryResponse(data: Any?) {
        val map = objectMap(data, "HabitSummaryResponse")
        exact(map, setOf("habit", "lifecycle_status", "today", "statistics", "reminder_settings", "challenge_time_progress", "remaining_days"), "HabitSummaryResponse")
        habitResponse(map["habit"]); enum(map, "lifecycle_status", "HabitSummaryResponse", setOf("upcoming", "active", "completed", "ended_early")); map["today"]?.let(::dailyStatusResponse)
        statisticsResponse(map["statistics"]); reminderSettingsResponse(map["reminder_settings"]); ratio(map, "challenge_time_progress", "HabitSummaryResponse"); integer(map, "remaining_days", "HabitSummaryResponse", 0, Int.MAX_VALUE)
        if (map["lifecycle_status"] == "upcoming" && map["today"] != null || map["lifecycle_status"] == "active" && map["today"] == null) violation("Habit summary lifecycle and today are inconsistent.", "HabitSummaryResponse.today")
    }

    private fun todayProgressResponse(data: Any?) {
        val map = objectMap(data, "HabitTodayProgressResponse")
        exact(map, setOf("as_of_date", "active_count", "done_count", "eligible_count", "skipped_count", "partial_count", "absent_count"), "HabitTodayProgressResponse")
        date(map, "as_of_date", "HabitTodayProgressResponse")
        val values = listOf("active_count", "done_count", "eligible_count", "skipped_count", "partial_count", "absent_count").associateWith { safeInteger(map, it, "HabitTodayProgressResponse", 0) }
        if (values.getValue("active_count") != values.getValue("eligible_count") + values.getValue("skipped_count") || values.getValue("eligible_count") != values.getValue("done_count") + values.getValue("partial_count") + values.getValue("absent_count")) violation("Today progress counts are inconsistent.", "HabitTodayProgressResponse")
    }

    private fun checkInResponse(data: Any?) {
        val map = objectMap(data, "HabitCheckInResponse")
        exact(map, setOf("id", "habit_id", "check_date", "status", "completed_count_hundredths", "target_count_snapshot_hundredths", "unit_snapshot", "completed_at", "note", "source", "created_at", "updated_at", "deleted_at"), "HabitCheckInResponse")
        uuid(map, "id", "HabitCheckInResponse"); uuid(map, "habit_id", "HabitCheckInResponse"); date(map, "check_date", "HabitCheckInResponse")
        val status = enum(map, "status", "HabitCheckInResponse", setOf("done", "partial", "skipped"))
        nullableSafeInteger(map, "completed_count_hundredths", "HabitCheckInResponse", 1); nullableSafeInteger(map, "target_count_snapshot_hundredths", "HabitCheckInResponse", 1); nullableBoundedString(map, "unit_snapshot", "HabitCheckInResponse", 1, 32); nullableUtc(map, "completed_at", "HabitCheckInResponse"); nullableBoundedString(map, "note", "HabitCheckInResponse", 0, 500)
        enum(map, "source", "HabitCheckInResponse", setOf("manual", "notification_action")); utc(map, "created_at", "HabitCheckInResponse"); utc(map, "updated_at", "HabitCheckInResponse")
        if (map["deleted_at"] != null) violation("HabitCheckInResponse must not expose tombstones.", "HabitCheckInResponse.deleted_at")
        val quantitative = map["completed_count_hundredths"] != null || map["target_count_snapshot_hundredths"] != null || map["unit_snapshot"] != null
        if (status == "skipped" && (quantitative || map["completed_at"] != null) || status in setOf("done", "partial") && map["completed_at"] == null || quantitative && listOf("completed_count_hundredths", "target_count_snapshot_hundredths", "unit_snapshot").any { map[it] == null } || status == "partial" && !quantitative) violation("Habit CheckIn status fields are inconsistent.", "HabitCheckInResponse.status")
    }

    private fun dailyStatusResponse(data: Any?) {
        val map = objectMap(data, "HabitDailyStatusResponse")
        exact(map, setOf("date", "status", "is_final", "check_in", "completion_ratio"), "HabitDailyStatusResponse")
        date(map, "date", "HabitDailyStatusResponse"); val status = enum(map, "status", "HabitDailyStatusResponse", setOf("upcoming", "absent", "partial", "done", "skipped", "missed")); val final = boolean(map, "is_final", "HabitDailyStatusResponse")
        val checkIn = map["check_in"]?.let {
            checkInResponse(it)
            objectMap(it, "HabitDailyStatusResponse.check_in")
        }
        nullableRatio(map, "completion_ratio", "HabitDailyStatusResponse")
        val ratio = (map["completion_ratio"] as? Number)?.toDouble()
        val valid = when (status) {
            "upcoming", "absent" -> checkIn == null && ratio == null && !final
            "missed" -> checkIn == null && ratio == null && final
            "skipped" -> checkIn?.get("status") == "skipped" && ratio == null && final
            "partial" -> checkIn?.get("status") == "partial" && ratio != null && ratio > 0.0 && ratio < 1.0
            "done" -> checkIn?.get("status") == "done" && ratio == 1.0 && final
            else -> false
        }
        if (!valid) violation("Habit daily status fields are inconsistent.", "HabitDailyStatusResponse.status")
    }

    private fun statisticsResponse(data: Any?) {
        val map = objectMap(data, "HabitStatisticsResponse")
        val counts = setOf("elapsed_eligible_days", "done_days", "skipped_days", "partial_days", "missed_days", "current_streak", "longest_streak")
        val rates = setOf("completion_rate_7_days", "completion_rate_30_days", "completion_rate_all")
        val quantities = setOf("quantity_progress_rate_7_days", "quantity_progress_rate_30_days", "quantity_progress_rate_all", "total_completed_count_hundredths", "average_completed_count_per_eligible_day_hundredths")
        exact(map, setOf("as_of_date") + counts + rates + quantities, "HabitStatisticsResponse")
        date(map, "as_of_date", "HabitStatisticsResponse"); counts.forEach { integer(map, it, "HabitStatisticsResponse", 0, Int.MAX_VALUE) }; rates.forEach { ratio(map, it, "HabitStatisticsResponse") }
        listOf("quantity_progress_rate_7_days", "quantity_progress_rate_30_days", "quantity_progress_rate_all").forEach { nullableRatio(map, it, "HabitStatisticsResponse") }
        nullableSafeInteger(map, "total_completed_count_hundredths", "HabitStatisticsResponse", 0); nullableSafeInteger(map, "average_completed_count_per_eligible_day_hundredths", "HabitStatisticsResponse", 0)
        val nullCount = quantities.count { map[it] == null }
        if (nullCount != 0 && nullCount != quantities.size) violation("Habit quantity statistics must be all null or all present.", "HabitStatisticsResponse")
    }

    private fun reminderSettingsResponse(data: Any?) {
        val map = objectMap(data, "HabitReminderSettingsResponse")
        exact(map, setOf("is_enabled", "template", "active_reminder_count", "schedule_reconciliation_required"), "HabitReminderSettingsResponse")
        val enabled = boolean(map, "is_enabled", "HabitReminderSettingsResponse"); val count = integer(map, "active_reminder_count", "HabitReminderSettingsResponse", 0, 1); boolean(map, "schedule_reconciliation_required", "HabitReminderSettingsResponse")
        val template = map["template"]?.let {
            reminderTemplateResponse(it)
            objectMap(it, "HabitReminderSettingsResponse.template")
        }
        if (enabled != (template?.get("is_enabled") == true) || !enabled && count != 0L) violation("Habit reminder settings are inconsistent.", "HabitReminderSettingsResponse")
    }

    private fun reminderTemplateResponse(data: Any?) {
        val map = objectMap(data, "HabitReminderTemplateResponse")
        exact(map, setOf("template_key", "habit_id", "local_time", "timezone_mode", "method", "is_enabled", "created_at", "updated_at", "deleted_at"), "HabitReminderTemplateResponse")
        uuid(map, "template_key", "HabitReminderTemplateResponse"); uuid(map, "habit_id", "HabitReminderTemplateResponse"); boundedString(map, "local_time", "HabitReminderTemplateResponse", 5, 5)
        if (!localTime.matches(map["local_time"] as String) || map["timezone_mode"] != "follow_device" || map["method"] != "popup" || map["deleted_at"] != null) violation("Habit reminder template is invalid.", "HabitReminderTemplateResponse")
        boolean(map, "is_enabled", "HabitReminderTemplateResponse"); utc(map, "created_at", "HabitReminderTemplateResponse"); utc(map, "updated_at", "HabitReminderTemplateResponse")
    }

    private fun paginationRequest(map: Map<String, Any?>) {
        ContractValidators.rejectUnknownFields(map, setOf("page", "page_size", "cursor", "sort_by", "sort_direction"), "ListHabitsRequest.pagination")
        nullableSafeInteger(map, "page", "ListHabitsRequest.pagination", 1); map["page_size"]?.let { integer(map, "page_size", "ListHabitsRequest.pagination", 1, 100) }; nullableBoundedString(map, "cursor", "ListHabitsRequest.pagination", 1, 512)
        if (map["sort_by"] != null || map["sort_direction"] != null) violation("Habit ordering is fixed.", "ListHabitsRequest.pagination.sort_by")
    }

    private fun paginationResponse(map: Map<String, Any?>) {
        exact(map, setOf("total", "page", "page_size", "has_more", "next_cursor"), "HabitListResponse.pagination")
        nullableSafeInteger(map, "total", "HabitListResponse.pagination", 0); nullableSafeInteger(map, "page", "HabitListResponse.pagination", 1); integer(map, "page_size", "HabitListResponse.pagination", 1, 100); val more = boolean(map, "has_more", "HabitListResponse.pagination"); nullableBoundedString(map, "next_cursor", "HabitListResponse.pagination", 1, 512)
        if (more && map["next_cursor"] == null) violation("Pagination continuation requires next_cursor.", "HabitListResponse.pagination.next_cursor")
    }

    private fun pairedQuantity(map: Map<String, Any?>, parent: String) {
        nullableSafeInteger(map, "target_count_hundredths", parent, 1); nullableBoundedString(map, "unit", parent, 1, 32)
        if ((map["target_count_hundredths"] == null) != (map["unit"] == null)) violation("Habit target and unit must both be null or present.", "$parent.target_count_hundredths")
    }

    private fun request(arguments: Any?, parent: String, validator: (Map<String, Any?>) -> Unit): V2JsonRequest = V2ContractPrimitives.request(arguments, parent, validator)
    private fun exact(map: Map<String, Any?>, fields: Set<String>, parent: String) = V2ContractPrimitives.requireExactFields(map, fields, parent)
    private fun allowedAndRequired(map: Map<String, Any?>, allowed: Set<String>, required: Set<String>, parent: String) { ContractValidators.rejectUnknownFields(map, allowed, parent); V2ContractPrimitives.requireFields(map, required, parent) }
    @Suppress("UNCHECKED_CAST") private fun objectMap(value: Any?, parent: String): Map<String, Any?> = value as? Map<String, Any?> ?: throw NativeContractViolation("$parent must be an object.", parent)
    @Suppress("UNCHECKED_CAST") private fun objectArray(value: Any?, parent: String, maximum: Int): List<Map<String, Any?>> { val list = value as? List<*> ?: throw NativeContractViolation("$parent must be an array.", parent); if (list.size > maximum) violation("$parent exceeds its item limit.", parent); return list.mapIndexed { i, item -> item as? Map<String, Any?> ?: throw NativeContractViolation("$parent[$i] must be an object.", "$parent[$i]") } }
    private fun uuid(map: Map<String, Any?>, key: String, parent: String): String { val value = boundedString(map, key, parent, 1, 64); try { UUID.fromString(value) } catch (_: IllegalArgumentException) { violation("$parent.$key must be UUID.", "$parent.$key") }; return value }
    private fun nullableUuid(map: Map<String, Any?>, key: String, parent: String) { if (map[key] != null) uuid(map, key, parent) }
    private fun date(map: Map<String, Any?>, key: String, parent: String): LocalDate { val value = boundedString(map, key, parent, 10, 10); return try { LocalDate.parse(value, dateFormatter) } catch (_: DateTimeException) { violation("$parent.$key must be a valid date.", "$parent.$key") } }
    private fun nullableDate(map: Map<String, Any?>, key: String, parent: String) { if (map[key] != null) date(map, key, parent) }
    private fun utc(map: Map<String, Any?>, key: String, parent: String): String { val value = boundedString(map, key, parent, 20, 20); if (!utcSecond.matches(value)) violation("$parent.$key must be a UTC second instant.", "$parent.$key"); try { Instant.parse(value) } catch (_: DateTimeException) { violation("$parent.$key must be a UTC instant.", "$parent.$key") }; return value }
    private fun nullableUtc(map: Map<String, Any?>, key: String, parent: String) { if (map[key] != null) utc(map, key, parent) }
    private fun timezone(map: Map<String, Any?>, key: String, parent: String): String { val value = boundedString(map, key, parent, 1, 255); if (value !in ZoneId.getAvailableZoneIds()) violation("$parent.$key must be an IANA timezone.", "$parent.$key"); return value }
    private fun boundedString(map: Map<String, Any?>, key: String, parent: String, minimum: Int, maximum: Int): String { if (!map.containsKey(key)) violation("$parent.$key is required.", "$parent.$key"); val value = map[key] as? String ?: violation("$parent.$key must be string.", "$parent.$key"); val count = value.codePointCount(0, value.length); if (count !in minimum..maximum) violation("$parent.$key length is out of range.", "$parent.$key"); return value }
    private fun nullableString(map: Map<String, Any?>, key: String, parent: String) { if (map[key] != null && map[key] !is String) violation("$parent.$key must be string or null.", "$parent.$key") }
    private fun nullableBoundedString(map: Map<String, Any?>, key: String, parent: String, minimum: Int, maximum: Int) { if (map[key] != null) boundedString(map, key, parent, minimum, maximum) }
    private fun boolean(map: Map<String, Any?>, key: String, parent: String): Boolean { if (!map.containsKey(key) || map[key] !is Boolean) violation("$parent.$key must be boolean.", "$parent.$key"); return map[key] as Boolean }
    private fun trueValue(map: Map<String, Any?>, key: String, parent: String) { if (map[key] != true) violation("$parent.$key must be true.", "$parent.$key") }
    private fun integer(map: Map<String, Any?>, key: String, parent: String, minimum: Int, maximum: Int): Long { val value = V2ContractPrimitives.integerValue(map[key]) ?: violation("$parent.$key must be integer.", "$parent.$key"); if (value !in minimum.toLong()..maximum.toLong()) violation("$parent.$key is out of range.", "$parent.$key"); return value }
    private fun safeInteger(map: Map<String, Any?>, key: String, parent: String, minimum: Long): Long { val value = V2ContractPrimitives.integerValue(map[key]) ?: violation("$parent.$key must be an exact integer.", "$parent.$key"); if (value !in minimum..MaxSafeInteger) violation("$parent.$key is outside JSON safe-integer range.", "$parent.$key"); return value }
    private fun nullableSafeInteger(map: Map<String, Any?>, key: String, parent: String, minimum: Long) { if (map[key] != null) safeInteger(map, key, parent, minimum) }
    private fun enum(map: Map<String, Any?>, key: String, parent: String, allowed: Set<String>): String { val value = map[key] as? String ?: violation("$parent.$key must be string.", "$parent.$key"); if (value !in allowed) violation("$parent.$key has an unsupported enum value.", "$parent.$key"); return value }
    private fun ratio(map: Map<String, Any?>, key: String, parent: String): Double { val value = (map[key] as? Number)?.toDouble() ?: violation("$parent.$key must be number.", "$parent.$key"); if (!value.isFinite() || value !in 0.0..1.0) violation("$parent.$key must be between zero and one.", "$parent.$key"); return value }
    private fun nullableRatio(map: Map<String, Any?>, key: String, parent: String) { if (map[key] != null) ratio(map, key, parent) }
    private fun stringArray(map: Map<String, Any?>, key: String, parent: String, minimum: Int, maximum: Int, allowed: Set<String>? = null, maximumCodePoints: Int? = null) { val value = map[key] ?: return; val list = value as? List<*> ?: violation("$parent.$key must be an array.", "$parent.$key"); if (list.size !in minimum..maximum || list.distinct().size != list.size) violation("$parent.$key size or uniqueness is invalid.", "$parent.$key"); list.forEachIndexed { i, item -> if (item !is String || allowed != null && item !in allowed || maximumCodePoints != null && item.codePointCount(0, item.length) !in 1..maximumCodePoints) violation("$parent.$key[$i] is invalid.", "$parent.$key[$i]") } }
    private fun validateDateRange(start: LocalDate, end: LocalDate, parent: String) { val days = ChronoUnit.DAYS.between(start, end) + 1; if (days !in 1..400) violation("$parent date range must contain 1..400 days.", "$parent.end_date") }
    private fun violation(message: String, field: String): Nothing = throw NativeContractViolation(message, field)
}

internal data class HabitReconcilePage(
    val processedCount: Int,
    val scheduleReconciliationRequired: Boolean,
    val hasMore: Boolean,
    val nextCursor: String?,
)
