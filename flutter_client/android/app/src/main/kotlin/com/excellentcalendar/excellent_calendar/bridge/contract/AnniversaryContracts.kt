package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import java.time.DateTimeException
import java.time.Instant
import java.time.LocalDate
import java.time.temporal.ChronoUnit

object AnniversaryRequestContracts {
    private val anniversaryFields = setOf(
        "title", "date", "calendar_type", "category_id", "recurrence", "note", "importance", "timezone",
    )

    fun create(arguments: Any?): V2JsonRequest = request(arguments, "CreateAnniversaryRequest") { map ->
        AnniversaryContractValidation.requireFields(
            map,
            required = anniversaryFields,
            allowed = anniversaryFields + "reminder_plan",
            parent = "CreateAnniversaryRequest",
        )
        AnniversaryContractValidation.anniversaryWriteFields(map, "CreateAnniversaryRequest")
        AnniversaryContractValidation.optionalReminderPlan(map, "CreateAnniversaryRequest")
    }

    fun update(arguments: Any?): V2JsonRequest = request(arguments, "UpdateAnniversaryRequest") { map ->
        val required = anniversaryFields + setOf("id", "expected_updated_at")
        AnniversaryContractValidation.requireFields(
            map,
            required = required,
            allowed = required + "reminder_plan",
            parent = "UpdateAnniversaryRequest",
        )
        AnniversaryContractValidation.uuid(map, "id", "UpdateAnniversaryRequest")
        AnniversaryContractValidation.updateToken(map, "expected_updated_at", "UpdateAnniversaryRequest")
        AnniversaryContractValidation.anniversaryWriteFields(map, "UpdateAnniversaryRequest")
        AnniversaryContractValidation.optionalReminderPlan(map, "UpdateAnniversaryRequest")
    }

    fun delete(arguments: Any?): V2JsonRequest = request(arguments, "DeleteAnniversaryRequest") { map ->
        AnniversaryContractValidation.requireExactFields(map, setOf("id"), "DeleteAnniversaryRequest")
        AnniversaryContractValidation.uuid(map, "id", "DeleteAnniversaryRequest")
    }

    fun detail(arguments: Any?): V2JsonRequest = request(arguments, "GetAnniversaryDetailRequest") { map ->
        AnniversaryContractValidation.requireExactFields(map, setOf("id", "timezone"), "GetAnniversaryDetailRequest")
        AnniversaryContractValidation.uuid(map, "id", "GetAnniversaryDetailRequest")
        AnniversaryContractValidation.timezone(map, "timezone", "GetAnniversaryDetailRequest")
    }

    fun list(arguments: Any?): V2JsonRequest = request(arguments, "ListAnniversariesRequest") { map ->
        val parent = "ListAnniversariesRequest"
        val allowed = setOf("timezone", "category_ids", "importance", "pagination", "sort_by", "sort_direction")
        ContractValidators.rejectUnknownFields(map, allowed, parent)
        AnniversaryContractValidation.timezone(map, "timezone", parent)
        AnniversaryContractValidation.optionalUuidArray(map, "category_ids", parent, allowEmpty = false)
        AnniversaryContractValidation.optionalEnumArray(
            map,
            "importance",
            parent,
            ContractEnums.Importance,
            allowEmpty = false,
        )
        AnniversaryContractValidation.optionalPagination(map, "pagination", parent)
        AnniversaryContractValidation.optionalEnum(
            map,
            "sort_by",
            parent,
            setOf("target_occurrence_date", "countdown_days"),
        )
        AnniversaryContractValidation.optionalEnum(map, "sort_direction", parent, ContractEnums.SortDirection)
    }

    fun previewCountdown(arguments: Any?): V2JsonRequest =
        request(arguments, "PreviewAnniversaryCountdownRequest") { map ->
            val parent = "PreviewAnniversaryCountdownRequest"
            AnniversaryContractValidation.requireExactFields(
                map,
                setOf("date", "calendar_type", "recurrence", "timezone"),
                parent,
            )
            AnniversaryContractValidation.localDate(map, "date", parent)
            AnniversaryContractValidation.enum(map, "calendar_type", parent, setOf("solar", "lunar"))
            AnniversaryContractValidation.recurrence(map, parent)
            AnniversaryContractValidation.timezone(map, "timezone", parent)
        }

    fun setRemindersEnabled(arguments: Any?): V2JsonRequest =
        request(arguments, "SetAnniversaryRemindersEnabledRequest") { map ->
            val parent = "SetAnniversaryRemindersEnabledRequest"
            AnniversaryContractValidation.requireExactFields(
                map,
                setOf("id", "reminders_enabled", "timezone"),
                parent,
            )
            AnniversaryContractValidation.uuid(map, "id", parent)
            AnniversaryContractValidation.boolean(map, "reminders_enabled", parent)
            AnniversaryContractValidation.timezone(map, "timezone", parent)
        }

    fun listOccurrences(arguments: Any?): V2JsonRequest =
        request(arguments, "ListAnniversaryOccurrencesRequest") { map ->
            val parent = "ListAnniversaryOccurrencesRequest"
            AnniversaryContractValidation.requireExactFields(
                map,
                setOf(
                    "range_start_date", "range_end_date", "timezone", "category_ids", "importance", "cursor", "page_size",
                ),
                parent,
            )
            val start = AnniversaryContractValidation.localDate(map, "range_start_date", parent)
            val end = AnniversaryContractValidation.localDate(map, "range_end_date", parent)
            if (ChronoUnit.DAYS.between(start, end) !in 1L..400L) {
                AnniversaryContractValidation.fail(
                    "$parent date range must contain between 1 and 400 natural days.",
                    "$parent.range_end_date",
                )
            }
            AnniversaryContractValidation.timezone(map, "timezone", parent)
            AnniversaryContractValidation.uuidArray(map, "category_ids", parent, maximum = 100, allowEmpty = true)
            AnniversaryContractValidation.enumArray(
                map,
                "importance",
                parent,
                ContractEnums.Importance,
                maximum = 4,
                allowEmpty = true,
            )
            AnniversaryContractValidation.nullableCursor(map, "cursor", parent)
            AnniversaryContractValidation.integerRange(map, "page_size", parent, 1, 500)
        }

    private fun request(
        arguments: Any?,
        parent: String,
        validator: (Map<String, Any?>) -> Unit,
    ): V2JsonRequest {
        val map = try {
            NativeContractJsonCodec.normalizeMap(arguments)
        } catch (error: IllegalArgumentException) {
            throw NativeContractViolation("$parent must be an object.", parent, error)
        }
        validator(map)
        return V2JsonRequest(map)
    }
}

object AnniversaryResponseContracts {
    fun nativeDetail(data: Any?) {
        AnniversaryContractValidation.detail(data, "AnniversaryDetailResponse")
    }

    fun nativeDeleteCommit(data: Any?) {
        AnniversaryContractValidation.deleteCommit(data, "AnniversaryDeleteCommitResponse")
    }

    fun detailView(data: Any?) {
        val parent = "AnniversaryDetailViewResponse"
        val map = AnniversaryContractValidation.objectMap(data, parent)
        AnniversaryContractValidation.requireExactFields(map, setOf("detail", "capability"), parent)
        AnniversaryContractValidation.detail(map["detail"], "$parent.detail")
        AnniversaryContractValidation.capability(map["capability"], "$parent.capability")
    }

    fun mutation(data: Any?) {
        val parent = "AnniversaryMutationResponse"
        val map = AnniversaryContractValidation.objectMap(data, parent)
        AnniversaryContractValidation.requireExactFields(map, setOf("data_saved", "detail", "capability"), parent)
        if (map["data_saved"] != true) {
            AnniversaryContractValidation.fail("$parent.data_saved must be true.", "$parent.data_saved")
        }
        val detail = AnniversaryContractValidation.detail(map["detail"], "$parent.detail")
        val capability = AnniversaryContractValidation.capability(map["capability"], "$parent.capability")
        AnniversaryContractValidation.requireMatchingReconciliation(detail, capability, parent)
    }

    fun deleteOperation(data: Any?) {
        val parent = "AnniversaryDeleteOperationResponse"
        val map = AnniversaryContractValidation.objectMap(data, parent)
        AnniversaryContractValidation.requireExactFields(map, setOf("data_saved", "commit", "capability"), parent)
        if (map["data_saved"] != true) {
            AnniversaryContractValidation.fail("$parent.data_saved must be true.", "$parent.data_saved")
        }
        AnniversaryContractValidation.deleteCommit(map["commit"], "$parent.commit")
        AnniversaryContractValidation.capability(map["capability"], "$parent.capability")
    }

    fun list(data: Any?) {
        val parent = "AnniversaryListResponse"
        val map = AnniversaryContractValidation.objectMap(data, parent)
        AnniversaryContractValidation.requireExactFields(map, setOf("items", "pagination"), parent)
        val items = map["items"] as? List<*> ?: AnniversaryContractValidation.fail(
            "$parent.items must be an array.",
            "$parent.items",
        )
        items.forEachIndexed { index, item ->
            val itemParent = "$parent.items[$index]"
            val summary = AnniversaryContractValidation.objectMap(item, itemParent)
            AnniversaryContractValidation.requireExactFields(summary, setOf("anniversary", "countdown"), itemParent)
            val anniversary = AnniversaryContractValidation.anniversaryResponse(
                summary["anniversary"],
                "$itemParent.anniversary",
            )
            if (anniversary["calendar_type"] != "solar" || anniversary["deleted_at"] != null) {
                AnniversaryContractValidation.fail(
                    "$itemParent must contain an active solar Anniversary.",
                    "$itemParent.anniversary",
                )
            }
            AnniversaryContractValidation.countdown(summary["countdown"], "$itemParent.countdown")
        }
        AnniversaryContractValidation.paginationResponse(map["pagination"], "$parent.pagination")
    }

    fun countdown(data: Any?) {
        AnniversaryContractValidation.countdown(data, "AnniversaryCountdownResponse")
    }

    fun occurrences(data: Any?) {
        val parent = "AnniversaryOccurrenceListResponse"
        val map = AnniversaryContractValidation.objectMap(data, parent)
        AnniversaryContractValidation.requireExactFields(map, setOf("items", "has_more", "next_cursor"), parent)
        val items = map["items"] as? List<*> ?: AnniversaryContractValidation.fail(
            "$parent.items must be an array.",
            "$parent.items",
        )
        if (items.size > 500) AnniversaryContractValidation.fail("$parent.items exceeds 500.", "$parent.items")
        var previousKey: String? = null
        items.forEachIndexed { index, item ->
            val occurrence = AnniversaryContractValidation.occurrence(item, "$parent.items[$index]")
            val key = listOf(
                occurrence["occurrence_date"] as String,
                occurrence["anniversary_id"] as String,
                occurrence["occurrence_key"] as String,
            ).joinToString("|")
            if (previousKey != null && previousKey!! >= key) {
                AnniversaryContractValidation.fail(
                    "$parent.items must be strictly sorted by occurrence_date, anniversary_id, occurrence_key.",
                    "$parent.items[$index]",
                )
            }
            previousKey = key
        }
        val hasMore = map["has_more"] as? Boolean ?: AnniversaryContractValidation.fail(
            "$parent.has_more must be boolean.",
            "$parent.has_more",
        )
        AnniversaryContractValidation.nullableCursor(map, "next_cursor", parent)
        if (hasMore != (map["next_cursor"] != null)) {
            AnniversaryContractValidation.fail(
                "$parent.next_cursor must be present exactly when has_more is true.",
                "$parent.next_cursor",
            )
        }
    }
}

internal object AnniversaryContractValidation {
    private val uuidPattern = Regex(
        "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$",
    )
    private val localTimePattern = Regex("^(?:[01][0-9]|2[0-3]):[0-5][0-9]$")
    private val cursorPattern = Regex("^annocc1\\.[A-Za-z0-9_-]{20,2048}$")
    private val updateTokenPattern = Regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
    private val anniversaryResponseFields = setOf(
        "id", "title", "date", "calendar_type", "category_id", "recurrence_id", "note", "importance",
        "created_at", "updated_at", "deleted_at",
    )
    private val scheduleStatuses = setOf(
        "not_required", "scheduled_exact", "scheduled_approximate", "pending_permission", "pending_reconciliation",
    )
    private val notificationPermissionStatuses = setOf(
        "granted", "denied", "not_required", "permanently_denied", "unknown",
    )
    private val exactAlarmPermissionStatuses = setOf("granted", "denied", "not_required", "unknown")
    private val degradationReasons = setOf(
        "notification_permission_unavailable", "exact_alarm_permission_unavailable", "scheduler_retry_required",
    )

    fun anniversaryWriteFields(map: Map<String, Any?>, parent: String) {
        nonEmptyString(map, "title", parent)
        localDate(map, "date", parent)
        enum(map, "calendar_type", parent, setOf("solar", "lunar"))
        nullableUuid(map, "category_id", parent)
        recurrence(map, parent)
        nullableString(map, "note", parent)
        enum(map, "importance", parent, ContractEnums.Importance)
        timezone(map, "timezone", parent)
    }

    fun optionalReminderPlan(map: Map<String, Any?>, parent: String) {
        if (!map.containsKey("reminder_plan")) return
        val plan = objectMap(map["reminder_plan"], "$parent.reminder_plan")
        requireExactFields(plan, setOf("reminders_enabled", "templates"), "$parent.reminder_plan")
        boolean(plan, "reminders_enabled", "$parent.reminder_plan")
        val templates = plan["templates"] as? List<*> ?: fail(
            "$parent.reminder_plan.templates must be an array.",
            "$parent.reminder_plan.templates",
        )
        if (templates.size > 5) fail(
            "$parent.reminder_plan.templates must contain at most 5 items.",
            "$parent.reminder_plan.templates",
        )
        val identities = templates.mapIndexed { index, value ->
            val templateParent = "$parent.reminder_plan.templates[$index]"
            val template = objectMap(value, templateParent)
            requireExactFields(template, setOf("advance_days", "local_time", "method", "is_enabled"), templateParent)
            integerRange(template, "advance_days", templateParent, 0, 365)
            localTime(template, "local_time", templateParent)
            if (template["method"] != "popup") fail("$templateParent.method must be popup.", "$templateParent.method")
            boolean(template, "is_enabled", templateParent)
            listOf(template["advance_days"].exactLong(), template["local_time"], template["method"])
        }
        if (identities.toSet().size != identities.size) fail(
            "$parent.reminder_plan.templates contains a duplicate identity tuple.",
            "$parent.reminder_plan.templates",
        )
    }

    fun recurrence(map: Map<String, Any?>, parent: String) {
        if (!map.containsKey("recurrence")) fail("$parent.recurrence is required.", "$parent.recurrence")
        val value = map["recurrence"] ?: return
        val recurrence = objectMap(value, "$parent.recurrence")
        requireExactFields(recurrence, setOf("frequency", "interval"), "$parent.recurrence")
        if (recurrence["frequency"] != "yearly") {
            fail("$parent.recurrence.frequency must be yearly.", "$parent.recurrence.frequency")
        }
        if (recurrence["interval"].exactLong() != 1L) {
            fail("$parent.recurrence.interval must be 1.", "$parent.recurrence.interval")
        }
    }

    fun detail(value: Any?, parent: String): Map<String, Any?> {
        val map = objectMap(value, parent)
        requireExactFields(map, setOf("anniversary", "recurrence", "countdown", "reminder_settings"), parent)
        val anniversary = anniversaryResponse(map["anniversary"], "$parent.anniversary")
        if (anniversary["calendar_type"] != "solar" || anniversary["deleted_at"] != null) {
            fail("$parent must contain an active solar Anniversary.", "$parent.anniversary")
        }
        val recurrence = map["recurrence"]?.let { recurrenceResponse(it, "$parent.recurrence") }
        if ((anniversary["recurrence_id"] == null) != (recurrence == null) ||
            (recurrence != null && anniversary["recurrence_id"] != recurrence["recurrence_id"])
        ) {
            fail("$parent recurrence identity is inconsistent.", "$parent.recurrence")
        }
        countdown(map["countdown"], "$parent.countdown")
        reminderSettings(map["reminder_settings"], "$parent.reminder_settings")
        return map
    }

    fun deleteCommit(value: Any?, parent: String): Map<String, Any?> {
        val map = objectMap(value, parent)
        requireExactFields(map, setOf("anniversary", "schedule_reconciliation_required"), parent)
        val anniversary = anniversaryResponse(map["anniversary"], "$parent.anniversary")
        if (anniversary["deleted_at"] == null) {
            fail("$parent.anniversary.deleted_at must be a UTC instant.", "$parent.anniversary.deleted_at")
        }
        boolean(map, "schedule_reconciliation_required", parent)
        return map
    }

    fun reminderSettings(value: Any?, parent: String): Map<String, Any?> {
        val map = objectMap(value, parent)
        requireExactFields(
            map,
            setOf("reminders_enabled", "templates", "active_reminder_count", "schedule_reconciliation_required"),
            parent,
        )
        val enabled = boolean(map, "reminders_enabled", parent)
        val templates = map["templates"] as? List<*> ?: fail("$parent.templates must be an array.", "$parent.templates")
        if (templates.size > 5) fail("$parent.templates must contain at most 5 items.", "$parent.templates")
        val identities = templates.mapIndexed { index, value ->
            val templateParent = "$parent.templates[$index]"
            val template = objectMap(value, templateParent)
            requireExactFields(
                template,
                setOf("template_key", "advance_days", "local_time", "timezone_mode", "method", "is_enabled"),
                templateParent,
            )
            uuid(template, "template_key", templateParent)
            integerRange(template, "advance_days", templateParent, 0, 365)
            localTime(template, "local_time", templateParent)
            if (template["timezone_mode"] != "follow_device") fail(
                "$templateParent.timezone_mode must be follow_device.",
                "$templateParent.timezone_mode",
            )
            if (template["method"] != "popup") fail("$templateParent.method must be popup.", "$templateParent.method")
            boolean(template, "is_enabled", templateParent)
            listOf(template["advance_days"].exactLong(), template["local_time"], template["method"])
        }
        if (identities.toSet().size != identities.size) fail("$parent.templates contains duplicate identities.", "$parent.templates")
        val activeCount = integerRange(map, "active_reminder_count", parent, 0, 5)
        val expectedActiveCount = if (enabled) {
            templates.count { (it as Map<*, *>)["is_enabled"] == true }.toLong()
        } else {
            0L
        }
        if (activeCount != expectedActiveCount) fail(
            "$parent.active_reminder_count is inconsistent with reminders_enabled and templates.",
            "$parent.active_reminder_count",
        )
        boolean(map, "schedule_reconciliation_required", parent)
        return map
    }

    fun capability(value: Any?, parent: String): Map<String, Any?> {
        val map = objectMap(value, parent)
        requireExactFields(
            map,
            setOf(
                "schedule_status", "schedule_reconciliation_required", "notification_permission_status",
                "exact_alarm_permission_status", "degradation_reasons",
            ),
            parent,
        )
        enum(map, "schedule_status", parent, scheduleStatuses)
        val required = boolean(map, "schedule_reconciliation_required", parent)
        enum(map, "notification_permission_status", parent, notificationPermissionStatuses)
        enum(map, "exact_alarm_permission_status", parent, exactAlarmPermissionStatuses)
        enumArray(map, "degradation_reasons", parent, degradationReasons, degradationReasons.size, allowEmpty = true)
        val status = map["schedule_status"] as String
        if ((status in setOf("pending_permission", "pending_reconciliation")) != required) {
            fail("$parent.schedule_reconciliation_required is inconsistent with schedule_status.", "$parent.schedule_status")
        }
        return map
    }

    fun requireMatchingReconciliation(
        detail: Map<String, Any?>,
        capability: Map<String, Any?>,
        parent: String,
    ) {
        val settings = detail["reminder_settings"] as Map<*, *>
        if (settings["schedule_reconciliation_required"] != capability["schedule_reconciliation_required"]) {
            fail("$parent detail and capability reconciliation flags must match.", "$parent.capability")
        }
    }

    fun anniversaryResponse(value: Any?, parent: String): Map<String, Any?> {
        val map = objectMap(value, parent)
        requireExactFields(map, anniversaryResponseFields, parent)
        uuid(map, "id", parent)
        nonEmptyString(map, "title", parent)
        localDate(map, "date", parent)
        val calendarType = map["calendar_type"]
        if (calendarType != null && calendarType !in setOf("solar", "lunar")) {
            fail("$parent.calendar_type has an unsupported enum value.", "$parent.calendar_type")
        }
        nullableUuid(map, "category_id", parent)
        nullableUuid(map, "recurrence_id", parent)
        nullableString(map, "note", parent)
        val importance = map["importance"]
        if (importance != null && importance !in ContractEnums.Importance) {
            fail("$parent.importance has an unsupported enum value.", "$parent.importance")
        }
        utcInstant(map, "created_at", parent, nullable = false)
        utcInstant(map, "updated_at", parent, nullable = false)
        utcInstant(map, "deleted_at", parent, nullable = true)
        return map
    }

    fun recurrenceResponse(value: Any?, parent: String): Map<String, Any?> {
        val map = objectMap(value, parent)
        requireExactFields(map, setOf("recurrence_id", "frequency", "interval"), parent)
        uuid(map, "recurrence_id", parent)
        if (map["frequency"] != "yearly" || map["interval"].exactLong() != 1L) {
            fail("$parent must contain yearly interval 1.", parent)
        }
        return map
    }

    fun countdown(value: Any?, parent: String) {
        val map = objectMap(value, parent)
        requireExactFields(
            map,
            setOf("relation", "days", "target_occurrence_date", "iso_weekday", "timezone", "calculated_at"),
            parent,
        )
        val relation = map["relation"]
        if (relation !in setOf("remaining", "elapsed", "today")) {
            fail("$parent.relation has an unsupported enum value.", "$parent.relation")
        }
        val days = map["days"].exactLong()
        if (days == null || days < 0 || (relation == "today" && days != 0L) || (relation != "today" && days < 1L)) {
            fail("$parent.days is inconsistent with relation.", "$parent.days")
        }
        localDate(map, "target_occurrence_date", parent)
        integerRange(map, "iso_weekday", parent, 1, 7)
        timezone(map, "timezone", parent)
        utcInstant(map, "calculated_at", parent, nullable = false)
    }

    fun occurrence(value: Any?, parent: String): Map<String, Any?> {
        val map = objectMap(value, parent)
        requireExactFields(
            map,
            setOf(
                "anniversary_id", "occurrence_key", "occurrence_date", "source_date", "title", "calendar_type",
                "is_repeating", "years_elapsed", "category_id", "importance", "has_active_reminders", "reminder_count",
            ),
            parent,
        )
        uuid(map, "anniversary_id", parent)
        uuid(map, "occurrence_key", parent)
        val occurrenceDate = localDate(map, "occurrence_date", parent)
        val sourceDate = localDate(map, "source_date", parent)
        nonEmptyString(map, "title", parent)
        if (map["calendar_type"] != "solar") fail("$parent.calendar_type must be solar.", "$parent.calendar_type")
        val repeating = boolean(map, "is_repeating", parent)
        val years = integerRange(map, "years_elapsed", parent, 0, null)
        nullableUuid(map, "category_id", parent)
        val importance = map["importance"]
        if (importance != null && importance !in ContractEnums.Importance) {
            fail("$parent.importance has an unsupported enum value.", "$parent.importance")
        }
        val hasReminders = boolean(map, "has_active_reminders", parent)
        val reminderCount = integerRange(map, "reminder_count", parent, 0, 5)
        if (hasReminders != (reminderCount > 0)) fail(
            "$parent.reminder_count is inconsistent with has_active_reminders.",
            "$parent.reminder_count",
        )
        if (!repeating && (occurrenceDate != sourceDate || years != 0L)) {
            fail("$parent one-time occurrence identity is inconsistent.", parent)
        }
        return map
    }

    fun paginationResponse(value: Any?, parent: String) {
        val map = objectMap(value, parent)
        requireExactFields(map, setOf("total", "page", "page_size", "has_more", "next_cursor"), parent)
        if (map["total"] != null) integerRange(map, "total", parent, 0, null)
        if (map["page"] != null) integerRange(map, "page", parent, 1, null)
        integerRange(map, "page_size", parent, 1, 200)
        boolean(map, "has_more", parent)
        nullableString(map, "next_cursor", parent)
    }

    fun optionalPagination(map: Map<String, Any?>, key: String, parent: String) {
        if (!map.containsKey(key)) return
        val pagination = objectMap(map[key], "$parent.$key")
        val allowed = setOf("page", "page_size", "cursor")
        ContractValidators.rejectUnknownFields(pagination, allowed, "$parent.$key")
        optionalIntegerRange(pagination, "page", "$parent.$key", 1, null)
        optionalIntegerRange(pagination, "page_size", "$parent.$key", 1, 200)
        optionalNullableString(pagination, "cursor", "$parent.$key")
    }

    fun optionalUuidArray(map: Map<String, Any?>, key: String, parent: String, allowEmpty: Boolean) {
        if (!map.containsKey(key)) return
        uuidArray(map, key, parent, maximum = null, allowEmpty = allowEmpty)
    }

    fun uuidArray(
        map: Map<String, Any?>,
        key: String,
        parent: String,
        maximum: Int?,
        allowEmpty: Boolean,
    ): List<String> {
        val values = map[key] as? List<*> ?: fail("$parent.$key must be an array.", "$parent.$key")
        if (!allowEmpty && values.isEmpty()) fail("$parent.$key must not be empty.", "$parent.$key")
        if (maximum != null && values.size > maximum) fail("$parent.$key exceeds $maximum items.", "$parent.$key")
        val strings = values.mapIndexed { index, value ->
            val string = value as? String ?: fail("$parent.$key[$index] must be a UUID.", "$parent.$key[$index]")
            validateUuid(string, "$parent.$key[$index]")
            string
        }
        if (strings.toSet().size != strings.size) fail("$parent.$key must contain unique values.", "$parent.$key")
        return strings
    }

    fun optionalEnumArray(
        map: Map<String, Any?>,
        key: String,
        parent: String,
        allowed: Set<String>,
        allowEmpty: Boolean,
    ) {
        if (!map.containsKey(key)) return
        enumArray(map, key, parent, allowed, maximum = null, allowEmpty = allowEmpty)
    }

    fun enumArray(
        map: Map<String, Any?>,
        key: String,
        parent: String,
        allowed: Set<String>,
        maximum: Int?,
        allowEmpty: Boolean,
    ): List<String> {
        val values = map[key] as? List<*> ?: fail("$parent.$key must be an array.", "$parent.$key")
        if (!allowEmpty && values.isEmpty()) fail("$parent.$key must not be empty.", "$parent.$key")
        if (maximum != null && values.size > maximum) fail("$parent.$key exceeds $maximum items.", "$parent.$key")
        if (values.any { it !is String || it !in allowed }) fail("$parent.$key contains an unsupported value.", "$parent.$key")
        if (values.toSet().size != values.size) fail("$parent.$key must contain unique values.", "$parent.$key")
        @Suppress("UNCHECKED_CAST")
        return values as List<String>
    }

    fun optionalEnum(map: Map<String, Any?>, key: String, parent: String, allowed: Set<String>) {
        if (!map.containsKey(key)) return
        val value = map[key]
        if (value != null && (value !is String || value !in allowed)) {
            fail("$parent.$key has an unsupported enum value.", "$parent.$key")
        }
    }

    fun requireFields(map: Map<String, Any?>, required: Set<String>, allowed: Set<String>, parent: String) {
        ContractValidators.rejectUnknownFields(map, allowed, parent)
        val missing = required.firstOrNull { !map.containsKey(it) }
        if (missing != null) fail("$parent.$missing is required.", "$parent.$missing")
    }

    fun requireExactFields(map: Map<String, Any?>, fields: Set<String>, parent: String) {
        requireFields(map, fields, fields, parent)
    }

    fun objectMap(value: Any?, parent: String): Map<String, Any?> {
        if (value !is Map<*, *>) fail("$parent must be an object.", parent)
        val result = linkedMapOf<String, Any?>()
        value.forEach { (key, entryValue) ->
            if (key !is String) fail("$parent contains a non-string key.", parent)
            result[key] = entryValue
        }
        return result
    }

    fun uuid(map: Map<String, Any?>, key: String, parent: String): String {
        val value = map[key] as? String ?: fail("$parent.$key must be a UUID.", "$parent.$key")
        validateUuid(value, "$parent.$key")
        return value
    }

    fun nullableUuid(map: Map<String, Any?>, key: String, parent: String): String? {
        if (!map.containsKey(key)) fail("$parent.$key is required.", "$parent.$key")
        val value = map[key] ?: return null
        if (value !is String) fail("$parent.$key must be a UUID or null.", "$parent.$key")
        validateUuid(value, "$parent.$key")
        return value
    }

    fun localDate(map: Map<String, Any?>, key: String, parent: String): LocalDate {
        val value = map[key] as? String ?: fail("$parent.$key must be a date.", "$parent.$key")
        return try {
            LocalDate.parse(value)
        } catch (_: DateTimeException) {
            fail("$parent.$key must be a valid YYYY-MM-DD date.", "$parent.$key")
        }
    }

    fun localTime(map: Map<String, Any?>, key: String, parent: String): String {
        val value = map[key] as? String ?: fail("$parent.$key must be HH:mm.", "$parent.$key")
        if (!localTimePattern.matches(value)) fail("$parent.$key must use zero-padded HH:mm.", "$parent.$key")
        return value
    }

    fun timezone(map: Map<String, Any?>, key: String, parent: String): String {
        val value = nonEmptyString(map, key, parent)
        return IanaTimezoneContract.require(value, "$parent.$key")
    }

    fun nonEmptyString(map: Map<String, Any?>, key: String, parent: String): String {
        val value = map[key]
        if (value !is String || value.isEmpty()) fail("$parent.$key must be a non-empty string.", "$parent.$key")
        return value
    }

    fun nullableString(map: Map<String, Any?>, key: String, parent: String): String? {
        if (!map.containsKey(key)) fail("$parent.$key is required.", "$parent.$key")
        val value = map[key]
        if (value != null && value !is String) fail("$parent.$key must be a string or null.", "$parent.$key")
        return value as String?
    }

    fun nullableCursor(map: Map<String, Any?>, key: String, parent: String) {
        val value = nullableString(map, key, parent) ?: return
        if (!cursorPattern.matches(value)) fail("$parent.$key is malformed.", "$parent.$key")
    }

    fun enum(map: Map<String, Any?>, key: String, parent: String, allowed: Set<String>) {
        val value = map[key]
        if (value !is String || value !in allowed) fail("$parent.$key has an unsupported enum value.", "$parent.$key")
    }

    fun boolean(map: Map<String, Any?>, key: String, parent: String): Boolean {
        return map[key] as? Boolean ?: fail("$parent.$key must be boolean.", "$parent.$key")
    }

    fun integerRange(
        map: Map<String, Any?>,
        key: String,
        parent: String,
        minimum: Long,
        maximum: Long?,
    ): Long {
        val value = map[key].exactLong()
        if (value == null || value < minimum || (maximum != null && value > maximum)) {
            fail("$parent.$key is not an exact integer in range.", "$parent.$key")
        }
        return value
    }

    fun utcInstant(map: Map<String, Any?>, key: String, parent: String, nullable: Boolean) {
        if (!map.containsKey(key)) fail("$parent.$key is required.", "$parent.$key")
        val value = map[key]
        if (value == null && nullable) return
        if (value !is String || !value.endsWith("Z")) fail("$parent.$key must be a UTC instant.", "$parent.$key")
        try {
            Instant.parse(value)
        } catch (_: DateTimeException) {
            fail("$parent.$key must be a valid UTC instant.", "$parent.$key")
        }
    }

    fun updateToken(map: Map<String, Any?>, key: String, parent: String) {
        utcInstant(map, key, parent, nullable = false)
        if (!updateTokenPattern.matches(map[key] as String)) {
            fail("$parent.$key must use second-precision UTC form YYYY-MM-DDTHH:mm:ssZ.", "$parent.$key")
        }
    }

    private fun optionalIntegerRange(
        map: Map<String, Any?>,
        key: String,
        parent: String,
        minimum: Long,
        maximum: Long?,
    ) {
        if (!map.containsKey(key) || map[key] == null) return
        integerRange(map, key, parent, minimum, maximum)
    }

    private fun optionalNullableString(map: Map<String, Any?>, key: String, parent: String) {
        if (!map.containsKey(key) || map[key] == null) return
        if (map[key] !is String) fail("$parent.$key must be a string or null.", "$parent.$key")
    }

    private fun validateUuid(value: String, field: String) {
        if (!uuidPattern.matches(value)) fail("$field must be a UUID.", field)
    }

    fun fail(message: String, field: String): Nothing = throw NativeContractViolation(message, field)

    private fun Any?.exactLong(): Long? = when (this) {
        is Byte -> toLong()
        is Short -> toLong()
        is Int -> toLong()
        is Long -> this
        is Float -> takeIf { isFinite() && toDouble() == toLong().toDouble() }?.toLong()
        is Double -> takeIf { isFinite() && this == toLong().toDouble() }?.toLong()
        else -> null
    }
}
