package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import java.time.DateTimeException
import java.time.Instant
import java.time.LocalDate
import java.time.temporal.ChronoUnit

/** Strict Native Contract v2 boundary for the read-only Calendar View projection. */
object CalendarContracts {
    private val sections = setOf("event", "habit", "anniversary")
    private val eventStatuses = setOf("pending", "in_progress", "overdue", "completed", "skipped")
    private val eventDayDisplays = setOf("all_day", "starts_at", "continues", "ends_at")
    private val habitStatuses = setOf("upcoming", "absent", "partial", "done", "skipped", "missed")
    private val importance = setOf(
        "unimportant_noturgent",
        "important_noturgent",
        "unimportant_urgent",
        "important_urgent",
    )
    private val snapshotPattern = Regex("^calsnap1\\.[A-Za-z0-9_-]{20,512}$")
    private val cursorPattern = Regex("^calcur1\\.[A-Za-z0-9_-]{20,2048}$")
    private val uuidPattern = Regex(
        "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$",
    )
    private val datePattern = Regex("^\\d{4}-\\d{2}-\\d{2}$")
    private val utcSecondPattern = Regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
    private val localTimePattern = Regex("^(?:[01]\\d|2[0-3]):[0-5]\\d$")

    fun rangeSummaryRequest(arguments: Any?): V2JsonRequest = request(
        arguments,
        "CalendarRangeSummaryRequest",
    ) { map, parent ->
        exact(map, setOf("range_start_date", "range_end_date", "timezone"), parent)
        val start = localDate(map, "range_start_date", parent)
        val end = localDate(map, "range_end_date", parent)
        val days = ChronoUnit.DAYS.between(start, end)
        when {
            days <= 0L -> fail(
                "$parent local-date range must be non-empty and forward.",
                "$parent.range_end_date",
                NativeErrorCodes.CalendarRangeInvalid,
            )
            days > MaximumRangeDays -> fail(
                "$parent local-date range must contain at most $MaximumRangeDays natural days.",
                "$parent.range_end_date",
                NativeErrorCodes.CalendarRangeTooLarge,
            )
        }
        timezone(map, "timezone", parent, NativeErrorCodes.TimezoneIdInvalid)
    }

    fun listDayItemsRequest(arguments: Any?): V2JsonRequest = request(
        arguments,
        "CalendarListDayItemsRequest",
    ) { map, parent ->
        exact(map, setOf("date", "timezone", "section", "snapshot_token", "cursor", "page_size"), parent)
        localDate(map, "date", parent)
        timezone(map, "timezone", parent, NativeErrorCodes.TimezoneIdInvalid)
        enum(map, "section", parent, sections)
        snapshotToken(map, "snapshot_token", parent, NativeErrorCodes.CalendarSnapshotInvalid)
        nullableCursor(map, "cursor", parent, NativeErrorCodes.CalendarCursorInvalid)
        integer(map, "page_size", parent, 1L, MaximumPageSize)
    }

    fun rangeSummaryResponse(data: Any?, request: Map<String, Any?>? = null) {
        val parent = "CalendarRangeSummaryResponse"
        val map = objectMap(data, parent)
        exact(
            map,
            setOf("range_start_date", "range_end_date", "timezone", "snapshot_token", "days"),
            parent,
        )
        val start = localDate(map, "range_start_date", parent)
        val end = localDate(map, "range_end_date", parent)
        val dayCount = ChronoUnit.DAYS.between(start, end)
        if (dayCount !in 1L..MaximumRangeDays) {
            fail("$parent range must contain between 1 and $MaximumRangeDays natural days.", "$parent.range_end_date")
        }
        timezone(map, "timezone", parent)
        snapshotToken(map, "snapshot_token", parent)
        val days = list(map, "days", parent)
        if (days.size.toLong() != dayCount) {
            fail("$parent.days must contain exactly one item per requested date.", "$parent.days")
        }
        days.forEachIndexed { index, value ->
            val dayParent = "$parent.days[$index]"
            val day = objectMap(value, dayParent)
            exact(day, setOf("date", "has_open_event", "has_pending_habit", "has_anniversary"), dayParent)
            val actualDate = localDate(day, "date", dayParent)
            if (actualDate != start.plusDays(index.toLong())) {
                fail("$parent.days must be gap-free and ordered by date.", "$dayParent.date")
            }
            boolean(day, "has_open_event", dayParent)
            boolean(day, "has_pending_habit", dayParent)
            boolean(day, "has_anniversary", dayParent)
        }
        request?.let {
            requireEcho(map, it, "range_start_date", parent)
            requireEcho(map, it, "range_end_date", parent)
            requireEcho(map, it, "timezone", parent)
        }
    }

    fun dayItemPage(data: Any?, request: Map<String, Any?>? = null) {
        val parent = "CalendarDayItemPage"
        val map = objectMap(data, parent)
        exact(
            map,
            setOf("date", "timezone", "section", "snapshot_token", "page_size", "items", "has_more", "next_cursor"),
            parent,
        )
        val date = localDate(map, "date", parent)
        timezone(map, "timezone", parent)
        val section = enum(map, "section", parent, sections)
        snapshotToken(map, "snapshot_token", parent)
        val pageSize = integer(map, "page_size", parent, 1L, MaximumPageSize)
        val items = list(map, "items", parent)
        if (items.size > pageSize) {
            fail("$parent.items exceeds page_size.", "$parent.items")
        }
        items.forEachIndexed { index, value ->
            val itemParent = "$parent.items[$index]"
            when (section) {
                "event" -> eventItem(value, itemParent)
                "habit" -> habitItem(value, itemParent, date)
                "anniversary" -> anniversaryItem(value, itemParent, date)
            }
        }
        val hasMore = boolean(map, "has_more", parent)
        val nextCursor = nullableCursor(map, "next_cursor", parent)
        if (hasMore && (items.isEmpty() || nextCursor == null)) {
            fail("$parent non-terminal page must contain items and next_cursor.", "$parent.next_cursor")
        }
        if (!hasMore && nextCursor != null) {
            fail("$parent terminal page must have next_cursor=null.", "$parent.next_cursor")
        }
        request?.let {
            listOf("date", "timezone", "section", "snapshot_token", "page_size").forEach { key ->
                requireEcho(map, it, key, parent)
            }
            val previousCursor = it["cursor"]
            if (nextCursor != null && nextCursor == previousCursor) {
                fail("$parent.next_cursor must advance.", "$parent.next_cursor")
            }
        }
    }

    private fun eventItem(value: Any?, parent: String) {
        val map = objectMap(value, parent)
        exact(
            map,
            setOf(
                "event_id", "title", "is_all_day", "is_recurring", "recurrence_revision",
                "occurrence_key", "occurrence_start_at", "occurrence_start_date", "start_at", "end_at",
                "start_date", "end_date", "day_display", "display_local_time", "status", "has_active_reminder",
            ),
            parent,
        )
        uuid(map, "event_id", parent)
        string(map, "title", parent, minimumLength = 1)
        val allDay = boolean(map, "is_all_day", parent)
        val recurring = boolean(map, "is_recurring", parent)
        val revision = nullableInteger(map, "recurrence_revision", parent, 1L, null)
        val occurrenceKey = nullableUuid(map, "occurrence_key", parent)
        val occurrenceStartAt = nullableUtcInstant(map, "occurrence_start_at", parent)
        val occurrenceStartDate = nullableLocalDate(map, "occurrence_start_date", parent)
        val startAt = nullableUtcInstant(map, "start_at", parent)
        val endAt = nullableUtcInstant(map, "end_at", parent)
        val startDate = nullableLocalDate(map, "start_date", parent)
        val endDate = nullableLocalDate(map, "end_date", parent)
        val dayDisplay = enum(map, "day_display", parent, eventDayDisplays)
        val displayLocalTime = nullableString(map, "display_local_time", parent, maximumLength = 5)
        enum(map, "status", parent, eventStatuses)
        boolean(map, "has_active_reminder", parent)

        if (allDay) {
            if (startAt != null || endAt != null || startDate == null || endDate == null || startDate >= endDate) {
                fail("$parent all-day time fields are inconsistent.", "$parent.is_all_day")
            }
            if (dayDisplay != "all_day" || displayLocalTime != null) {
                fail("$parent all-day display fields are inconsistent.", "$parent.day_display")
            }
        } else {
            if (startAt == null || endAt == null || startAt >= endAt || startDate != null || endDate != null) {
                fail("$parent timed fields are inconsistent.", "$parent.is_all_day")
            }
            if (dayDisplay == "all_day") {
                fail("$parent timed item cannot use all_day display.", "$parent.day_display")
            }
            val requiresTime = dayDisplay == "starts_at" || dayDisplay == "ends_at"
            if (requiresTime != (displayLocalTime != null) ||
                (displayLocalTime != null && !localTimePattern.matches(displayLocalTime))
            ) {
                fail("$parent.display_local_time is inconsistent with day_display.", "$parent.display_local_time")
            }
        }

        if (!recurring) {
            if (revision != null || occurrenceKey != null || occurrenceStartAt != null || occurrenceStartDate != null) {
                fail("$parent non-recurring occurrence identity must be null.", "$parent.is_recurring")
            }
        } else if (revision == null || occurrenceKey == null ||
            (allDay && (occurrenceStartAt != null || occurrenceStartDate == null)) ||
            (!allDay && (occurrenceStartAt == null || occurrenceStartDate != null))
        ) {
            fail("$parent recurring occurrence identity is incomplete.", "$parent.is_recurring")
        }
    }

    private fun habitItem(value: Any?, parent: String, selectedDate: LocalDate) {
        val map = objectMap(value, parent)
        exact(
            map,
            setOf(
                "habit_id", "date", "title", "status", "check_in_id", "completed_count_hundredths",
                "target_count_hundredths", "unit", "has_active_reminder",
            ),
            parent,
        )
        uuid(map, "habit_id", parent)
        if (localDate(map, "date", parent) != selectedDate) {
            fail("$parent.date must match the page date.", "$parent.date")
        }
        string(map, "title", parent, minimumLength = 1, maximumLength = 80)
        val status = enum(map, "status", parent, habitStatuses)
        val checkInId = nullableUuid(map, "check_in_id", parent)
        val completed = nullableInteger(map, "completed_count_hundredths", parent, 1L, MaximumSafeInteger)
        val target = nullableInteger(map, "target_count_hundredths", parent, 1L, MaximumSafeInteger)
        val unit = nullableString(map, "unit", parent, minimumLength = 1, maximumLength = 32)
        boolean(map, "has_active_reminder", parent)

        if ((target == null) != (unit == null)) {
            fail("$parent target and unit must both be null or both be present.", "$parent.target_count_hundredths")
        }
        when (status) {
            "upcoming", "absent", "missed" -> if (checkInId != null || completed != null) {
                fail("$parent status cannot carry CheckIn progress.", "$parent.status")
            }
            "partial" -> if (
                checkInId == null || completed == null || target == null || unit == null || completed >= target
            ) {
                fail(
                    "$parent partial status requires quantity progress strictly below its target.",
                    "$parent.status",
                )
            }
            "done" -> if (checkInId == null ||
                !((completed == null && target == null && unit == null) ||
                    (completed != null && target != null && unit != null && completed >= target))
            ) {
                fail("$parent done status has inconsistent CheckIn progress.", "$parent.status")
            }
            "skipped" -> if (checkInId == null || completed != null) {
                fail("$parent skipped status requires a CheckIn without progress.", "$parent.status")
            }
        }
    }

    private fun anniversaryItem(value: Any?, parent: String, selectedDate: LocalDate) {
        val map = objectMap(value, parent)
        exact(
            map,
            setOf(
                "anniversary_id", "occurrence_key", "occurrence_date", "source_date", "title",
                "is_repeating", "years_elapsed", "importance", "has_active_reminder",
            ),
            parent,
        )
        uuid(map, "anniversary_id", parent)
        uuid(map, "occurrence_key", parent)
        val occurrenceDate = localDate(map, "occurrence_date", parent)
        if (occurrenceDate != selectedDate) {
            fail("$parent.occurrence_date must match the page date.", "$parent.occurrence_date")
        }
        localDate(map, "source_date", parent)
        string(map, "title", parent, minimumLength = 1)
        val repeating = boolean(map, "is_repeating", parent)
        val years = integer(map, "years_elapsed", parent, 0L, MaximumSafeInteger)
        nullableEnum(map, "importance", parent, importance)
        boolean(map, "has_active_reminder", parent)
        if (!repeating && years != 0L) {
            fail("$parent one-time Anniversary must have years_elapsed=0.", "$parent.years_elapsed")
        }
    }

    private fun request(
        arguments: Any?,
        parent: String,
        validator: (Map<String, Any?>, String) -> Unit,
    ): V2JsonRequest {
        val map = try {
            NativeContractJsonCodec.normalizeMap(arguments)
        } catch (error: IllegalArgumentException) {
            throw NativeContractViolation("$parent must be an object.", parent, error)
        }
        validator(map, parent)
        return V2JsonRequest(map)
    }

    private fun exact(map: Map<String, Any?>, fields: Set<String>, parent: String) {
        ContractValidators.rejectUnknownFields(map, fields, parent)
        fields.firstOrNull { !map.containsKey(it) }?.let { key ->
            fail("$parent.$key is required.", "$parent.$key")
        }
    }

    private fun objectMap(value: Any?, parent: String): Map<String, Any?> {
        if (value !is Map<*, *>) fail("$parent must be an object.", parent)
        return buildMap {
            value.forEach { (key, entry) ->
                if (key !is String) fail("$parent contains a non-string key.", parent)
                put(key, entry)
            }
        }
    }

    private fun list(map: Map<String, Any?>, key: String, parent: String): List<Any?> =
        map[key] as? List<*> ?: fail("$parent.$key must be an array.", "$parent.$key")

    private fun localDate(map: Map<String, Any?>, key: String, parent: String): LocalDate {
        val value = map[key] as? String ?: fail("$parent.$key must be a date.", "$parent.$key")
        if (!datePattern.matches(value)) fail("$parent.$key must use YYYY-MM-DD.", "$parent.$key")
        return try {
            LocalDate.parse(value)
        } catch (_: DateTimeException) {
            fail("$parent.$key must be a valid date.", "$parent.$key")
        }
    }

    private fun nullableLocalDate(map: Map<String, Any?>, key: String, parent: String): LocalDate? {
        if (!map.containsKey(key)) fail("$parent.$key is required.", "$parent.$key")
        if (map[key] == null) return null
        return localDate(map, key, parent)
    }

    private fun nullableUtcInstant(map: Map<String, Any?>, key: String, parent: String): Instant? {
        if (!map.containsKey(key)) fail("$parent.$key is required.", "$parent.$key")
        val value = map[key] ?: return null
        if (value !is String || !utcSecondPattern.matches(value)) {
            fail("$parent.$key must be a second-precision UTC instant or null.", "$parent.$key")
        }
        return try {
            Instant.parse(value)
        } catch (_: DateTimeException) {
            fail("$parent.$key must be a valid UTC instant.", "$parent.$key")
        }
    }

    private fun timezone(
        map: Map<String, Any?>,
        key: String,
        parent: String,
        errorCode: String = NativeErrorCodes.ContractValidationFailed,
    ): String {
        val value = string(map, key, parent, minimumLength = 1, maximumLength = 255)
        return try {
            IanaTimezoneContract.require(value, "$parent.$key")
        } catch (error: NativeContractViolation) {
            fail(error.message ?: "$parent.$key must be an IANA timezone.", "$parent.$key", errorCode, error)
        }
    }

    private fun snapshotToken(
        map: Map<String, Any?>,
        key: String,
        parent: String,
        errorCode: String = NativeErrorCodes.ContractValidationFailed,
    ): String {
        val value = map[key] as? String
            ?: fail("$parent.$key must be a snapshot token.", "$parent.$key", errorCode)
        if (!snapshotPattern.matches(value)) {
            fail("$parent.$key is malformed.", "$parent.$key", errorCode)
        }
        return value
    }

    private fun nullableCursor(
        map: Map<String, Any?>,
        key: String,
        parent: String,
        errorCode: String = NativeErrorCodes.ContractValidationFailed,
    ): String? {
        if (!map.containsKey(key)) fail("$parent.$key is required.", "$parent.$key")
        val value = map[key] ?: return null
        if (value !is String || !cursorPattern.matches(value)) {
            fail("$parent.$key is malformed.", "$parent.$key", errorCode)
        }
        return value
    }

    private fun uuid(map: Map<String, Any?>, key: String, parent: String): String {
        val value = map[key] as? String ?: fail("$parent.$key must be a UUID.", "$parent.$key")
        if (!uuidPattern.matches(value)) fail("$parent.$key must be a UUID.", "$parent.$key")
        return value
    }

    private fun nullableUuid(map: Map<String, Any?>, key: String, parent: String): String? {
        if (!map.containsKey(key)) fail("$parent.$key is required.", "$parent.$key")
        val value = map[key] ?: return null
        if (value !is String || !uuidPattern.matches(value)) {
            fail("$parent.$key must be a UUID or null.", "$parent.$key")
        }
        return value
    }

    private fun string(
        map: Map<String, Any?>,
        key: String,
        parent: String,
        minimumLength: Int = 0,
        maximumLength: Int? = null,
    ): String {
        val value = map[key] as? String ?: fail("$parent.$key must be a string.", "$parent.$key")
        val length = value.codePointCount(0, value.length)
        if (length < minimumLength || (maximumLength != null && length > maximumLength)) {
            fail("$parent.$key length is out of range.", "$parent.$key")
        }
        return value
    }

    private fun nullableString(
        map: Map<String, Any?>,
        key: String,
        parent: String,
        minimumLength: Int = 0,
        maximumLength: Int? = null,
    ): String? {
        if (!map.containsKey(key)) fail("$parent.$key is required.", "$parent.$key")
        val value = map[key] ?: return null
        if (value !is String) fail("$parent.$key must be a string or null.", "$parent.$key")
        val length = value.codePointCount(0, value.length)
        if (length < minimumLength || (maximumLength != null && length > maximumLength)) {
            fail("$parent.$key length is out of range.", "$parent.$key")
        }
        return value
    }

    private fun enum(map: Map<String, Any?>, key: String, parent: String, allowed: Set<String>): String {
        val value = map[key]
        if (value !is String || value !in allowed) {
            fail("$parent.$key has an unsupported enum value.", "$parent.$key")
        }
        return value
    }

    private fun nullableEnum(map: Map<String, Any?>, key: String, parent: String, allowed: Set<String>): String? {
        if (!map.containsKey(key)) fail("$parent.$key is required.", "$parent.$key")
        val value = map[key] ?: return null
        if (value !is String || value !in allowed) {
            fail("$parent.$key has an unsupported enum value.", "$parent.$key")
        }
        return value
    }

    private fun boolean(map: Map<String, Any?>, key: String, parent: String): Boolean =
        map[key] as? Boolean ?: fail("$parent.$key must be boolean.", "$parent.$key")

    private fun integer(
        map: Map<String, Any?>,
        key: String,
        parent: String,
        minimum: Long,
        maximum: Long?,
    ): Long {
        val value = exactLong(map[key])
        if (value == null || value < minimum || (maximum != null && value > maximum)) {
            fail("$parent.$key must be an integer in range.", "$parent.$key")
        }
        return value
    }

    private fun nullableInteger(
        map: Map<String, Any?>,
        key: String,
        parent: String,
        minimum: Long,
        maximum: Long?,
    ): Long? {
        if (!map.containsKey(key)) fail("$parent.$key is required.", "$parent.$key")
        if (map[key] == null) return null
        return integer(map, key, parent, minimum, maximum)
    }

    private fun exactLong(value: Any?): Long? = when (value) {
        is Byte -> value.toLong()
        is Short -> value.toLong()
        is Int -> value.toLong()
        is Long -> value
        else -> null
    }

    private fun requireEcho(
        response: Map<String, Any?>,
        request: Map<String, Any?>,
        key: String,
        parent: String,
    ) {
        val responseValue = response[key]
        val requestValue = request[key]
        val matches = if (exactLong(responseValue) != null && exactLong(requestValue) != null) {
            exactLong(responseValue) == exactLong(requestValue)
        } else {
            responseValue == requestValue
        }
        if (!matches) {
            fail("$parent.$key must echo the accepted request.", "$parent.$key")
        }
    }

    private fun fail(
        message: String,
        field: String,
        errorCode: String = NativeErrorCodes.ContractValidationFailed,
        cause: Throwable? = null,
    ): Nothing = throw NativeContractViolation(message, field, cause, errorCode)

    private const val MaximumRangeDays = 42L
    private const val MaximumPageSize = 100L
    private const val MaximumSafeInteger = 9_007_199_254_740_991L
}
