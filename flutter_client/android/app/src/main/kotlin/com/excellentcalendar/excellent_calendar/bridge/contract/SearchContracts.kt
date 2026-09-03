package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.time.DateTimeException
import java.time.Instant
import java.time.LocalDate

data class ReplaceSearchHistoryRequestContract(
    val expectedRevision: Long,
    val items: List<String>,
)

/** Strict Revision 2 boundary validation for unified Search and device-local history. */
object SearchContracts {
    fun queryRequest(arguments: Any?): V2JsonRequest = request(arguments, QueryRequest) { map, parent ->
        exact(map, QueryRequestFields, parent)
        safeInteger(map, "query_generation", parent)
        val keyword = string(map, "keyword", parent)
        SearchTextContract.requireQueryKeyword(keyword, "$parent.keyword")
        timezone(map, "timezone", parent)

        val targetTypes = stringList(map, "target_types", parent, 1, 3)
        requireCanonicalValues(targetTypes, TargetOrder, "$parent.target_types", NativeErrorCodes.SearchQueryInvalid)

        val dateFrom = nullableDate(map, "date_from", parent)
        val dateTo = nullableDate(map, "date_to_exclusive", parent)
        if ((dateFrom == null) != (dateTo == null) || (dateFrom != null && dateFrom >= dateTo)) {
            fail("Search date range must be a non-empty half-open pair.", "$parent.date_from", NativeErrorCodes.SearchQueryInvalid)
        }

        val categoryIds = nullableStringList(map, "category_ids", parent, 0, 100, maximumItemLength = 512)
        val includeUncategorized = boolean(map, "include_uncategorized", parent)
        if ((categoryIds == null && includeUncategorized) || (categoryIds != null && categoryIds.isEmpty() && !includeUncategorized)) {
            fail("Search category filter is invalid.", "$parent.category_ids", NativeErrorCodes.SearchQueryInvalid)
        }
        categoryIds?.let { requireUnique(it, "$parent.category_ids", NativeErrorCodes.SearchQueryInvalid) }
        boolean(map, "include_completed", parent)
        enum(map, "sort_by", parent, SortValues)

        val sections = objectList(map, "sections", parent, 1, 3)
        val sectionTargets = mutableListOf<String>()
        val cursors = mutableListOf<String?>()
        sections.forEachIndexed { index, section ->
            val sectionParent = "$parent.sections[$index]"
            exact(section, SectionRequestFields, sectionParent)
            val target = enum(section, "target_type", sectionParent, TargetValues)
            if (target !in targetTypes) {
                fail("Search section target must belong to target_types.", "$sectionParent.target_type", NativeErrorCodes.SearchQueryInvalid)
            }
            integer(section, "page_size", sectionParent, FixedPageSize, FixedPageSize)
            sectionTargets += target
            cursors += nullableCursor(section, "cursor", sectionParent)
        }
        requireCanonicalValues(sectionTargets, TargetOrder, "$parent.sections", NativeErrorCodes.SearchQueryInvalid)
        if (sections.size > 1 && (sectionTargets != targetTypes || cursors.any { it != null })) {
            fail(
                "Multi-section Search requests must be the cursor-free first page for every target.",
                "$parent.sections",
                NativeErrorCodes.SearchQueryInvalid,
            )
        }
    }

    fun replaceHistoryRequest(arguments: Any?): ReplaceSearchHistoryRequestContract {
        val map = normalizeObject(arguments, ReplaceHistoryRequest)
        exact(map, ReplaceHistoryRequestFields, ReplaceHistoryRequest)
        val expected = safeInteger(map, "expected_revision", ReplaceHistoryRequest)
        val items = stringList(map, "items", ReplaceHistoryRequest, 0, MaximumHistoryItems)
        SearchTextContract.requireCanonicalHistory(items, "$ReplaceHistoryRequest.items")
        return ReplaceSearchHistoryRequestContract(expected, items)
    }

    fun queryResponse(data: Any?, request: Map<String, Any?>) {
        val parent = QueryResponse
        val map = objectMap(data, parent)
        exact(map, QueryResponseFields, parent)
        val generation = safeInteger(map, "query_generation", parent)
        if (generation != exactLong(request["query_generation"])) {
            fail("Search response must echo query_generation.", "$parent.query_generation")
        }
        val normalizedKeyword = string(map, "normalized_keyword", parent)
        SearchTextContract.requireCanonicalNormalized(normalizedKeyword, "$parent.normalized_keyword")
        if (normalizedKeyword != SearchTextContract.normalize(request["keyword"] as String)) {
            fail("Search response normalized_keyword does not match the accepted request.", "$parent.normalized_keyword")
        }
        val responseTimezone = timezone(map, "timezone", parent)
        if (responseTimezone != request["timezone"]) {
            fail("Search response must echo timezone.", "$parent.timezone")
        }
        utcInstant(map, "evaluated_at", parent)
        snapshotToken(map, "snapshot_token", parent)

        val requestSections = objectList(request, "sections", QueryRequest, 1, 3)
        val responseSections = objectList(map, "sections", parent, 1, 3)
        if (responseSections.size != requestSections.size) {
            fail("Search response must contain every requested section.", "$parent.sections")
        }
        val identities = mutableSetOf<String>()
        responseSections.forEachIndexed { index, section ->
            val sectionParent = "$parent.sections[$index]"
            val requestSection = requestSections[index]
            val target = validateSection(section, requestSection, sectionParent, identities)
            if (target != requestSection["target_type"]) {
                fail("Search response section order must match the request.", "$sectionParent.target_type")
            }
        }
    }

    fun historyResponse(data: Any?) {
        val parent = "SearchHistoryResponse"
        val map = objectMap(data, parent)
        exact(map, HistoryResponseFields, parent)
        safeInteger(map, "revision", parent)
        val items = stringList(map, "items", parent, 0, MaximumHistoryItems)
        SearchTextContract.requireCanonicalHistory(items, "$parent.items")
    }

    private fun validateSection(
        map: Map<String, Any?>,
        request: Map<String, Any?>,
        parent: String,
        identities: MutableSet<String>,
    ): String {
        exact(map, SectionResponseFields, parent)
        val target = enum(map, "target_type", parent, TargetValues)
        val items = list(map, "items", parent)
        if (items.size > FixedPageSize.toInt()) fail("Search section exceeds fixed page size.", "$parent.items")
        val total = safeInteger(map, "total_count", parent)
        if (total < items.size) fail("Search total_count cannot be below returned items.", "$parent.total_count")
        val hasMore = boolean(map, "has_more", parent)
        val nextCursor = nullableCursor(map, "next_cursor", parent, response = true)
        if (hasMore != (nextCursor != null) || (hasMore && items.isEmpty())) {
            fail("Search pagination flags and cursor are inconsistent.", "$parent.next_cursor")
        }
        val initial = request["cursor"] == null
        if (initial) {
            val expectedCount = minOf(total, FixedPageSize).toInt()
            if (items.size != expectedCount || hasMore != (items.size.toLong() < total)) {
                fail("Search first page does not conserve total_count.", "$parent.items")
            }
        } else {
            if (hasMore && items.size != FixedPageSize.toInt()) {
                fail("Non-terminal continuation pages must be full.", "$parent.items")
            }
            if (nextCursor != null && nextCursor == request["cursor"]) {
                fail("Search next_cursor must advance.", "$parent.next_cursor")
            }
        }

        items.forEachIndexed { index, value ->
            val itemParent = "$parent.items[$index]"
            val identity = when (target) {
                "event" -> eventItem(value, itemParent)
                "habit" -> habitItem(value, itemParent)
                "anniversary" -> anniversaryItem(value, itemParent)
                else -> error("validated target")
            }
            if (!identities.add("$target:$identity")) {
                fail("Search response contains a duplicate target identity.", "$itemParent.target_id")
            }
        }
        return target
    }

    private fun eventItem(value: Any?, parent: String): String {
        val map = objectMap(value, parent)
        exact(map, EventFields, parent)
        if (enum(map, "target_type", parent, setOf("event")) != "event") error("validated discriminator")
        val id = uuid(map, "target_id", parent)
        text(map, "title", parent, minimum = 1)
        val category = category(map["category"], "$parent.category")
        val location = nullableText(map, "location", parent)
        match(map["match"], "$parent.match", EventMatchOrder, category != null, location != null)
        utcInstant(map, "updated_at", parent)
        enum(map, "status", parent, EventStatuses)
        val allDay = boolean(map, "is_all_day", parent)
        val recurring = boolean(map, "is_recurring", parent)
        val occurAt = nullableUtcInstant(map, "occur_at", parent)
        val occurDate = nullableDate(map, "occur_date", parent)
        if (allDay == (occurDate == null) || allDay == (occurAt != null)) {
            fail("Event date and datetime projection is inconsistent.", "$parent.is_all_day")
        }
        val revision = nullableInteger(map, "recurrence_revision", parent, 1, null)
        val occurrenceKey = nullableUuid(map, "occurrence_key", parent)
        if ((recurring && (revision == null || occurrenceKey == null)) ||
            (!recurring && (revision != null || occurrenceKey != null))
        ) {
            fail("Event recurrence navigation identity is inconsistent.", "$parent.is_recurring")
        }
        return id
    }

    private fun habitItem(value: Any?, parent: String): String {
        val map = objectMap(value, parent)
        exact(map, HabitFields, parent)
        enum(map, "target_type", parent, setOf("habit"))
        val id = uuid(map, "target_id", parent)
        text(map, "title", parent, 1, 80)
        val category = category(map["category"], "$parent.category")
        match(map["match"], "$parent.match", HabitMatchOrder, category != null, true)
        utcInstant(map, "updated_at", parent)
        val status = enum(map, "lifecycle_status", parent, HabitStatuses)
        localDate(map, "occur_date", parent)
        localDate(map, "challenge_start_date", parent)
        localDate(map, "challenge_end_date", parent)
        nullableDate(map, "ended_date", parent)
        val remaining = integer(map, "remaining_days", parent, 0, 400)
        if (status in setOf("completed", "ended_early") && remaining != 0L) {
            fail("Closed Habit must have zero remaining days.", "$parent.remaining_days")
        }
        val target = nullableInteger(map, "target_count_hundredths", parent, 1, MaximumSafeInteger)
        val unit = nullableText(map, "unit", parent, 1, 32)
        if ((target == null) != (unit == null)) {
            fail("Habit target and unit must both be null or present.", "$parent.target_count_hundredths")
        }
        return id
    }

    private fun anniversaryItem(value: Any?, parent: String): String {
        val map = objectMap(value, parent)
        exact(map, AnniversaryFields, parent)
        enum(map, "target_type", parent, setOf("anniversary"))
        val id = uuid(map, "target_id", parent)
        text(map, "title", parent, minimum = 1)
        val category = category(map["category"], "$parent.category")
        match(map["match"], "$parent.match", AnniversaryMatchOrder, category != null, true)
        utcInstant(map, "updated_at", parent)
        uuid(map, "occurrence_key", parent)
        localDate(map, "occur_date", parent)
        localDate(map, "source_date", parent)
        val repeating = boolean(map, "is_repeating", parent)
        val relation = enum(map, "relation", parent, AnniversaryRelations)
        val days = integer(map, "days", parent, 0, null)
        if ((relation == "today") != (days == 0L)) {
            fail("Anniversary relation and days are inconsistent.", "$parent.days")
        }
        val years = integer(map, "years_elapsed", parent, 0, null)
        if (!repeating && years != 0L) {
            fail("One-time Anniversary must have zero elapsed years.", "$parent.years_elapsed")
        }
        return id
    }

    private fun category(value: Any?, parent: String): Map<String, Any?>? {
        if (value == null) return null
        val map = objectMap(value, parent)
        exact(map, CategoryFields, parent)
        val id = string(map, "id", parent)
        if (!CategoryUuidPattern.matches(id)) fail("$parent.id must be a lowercase UUIDv4.", "$parent.id")
        text(map, "name", parent, 1, 40)
        val color = nullableText(map, "color", parent)
        if (color != null && !ColorPattern.matches(color)) fail("$parent.color is invalid.", "$parent.color")
        nullableText(map, "icon", parent, 1, 64)
        return map
    }

    private fun match(
        value: Any?,
        parent: String,
        allowedOrder: List<String>,
        hasCategory: Boolean,
        locationAvailable: Boolean,
    ) {
        val map = objectMap(value, parent)
        exact(map, MatchFields, parent)
        val primary = enum(map, "primary_field", parent, allowedOrder.toSet())
        val matched = stringList(map, "matched_fields", parent, 1, allowedOrder.size)
        requireCanonicalValues(matched, allowedOrder, "$parent.matched_fields", NativeErrorCodes.ContractValidationFailed)
        if (primary !in matched) fail("Search primary_field must be matched.", "$parent.primary_field")
        if ("category_name" in matched && !hasCategory) {
            fail("Category matches require a current Category projection.", "$parent.matched_fields")
        }
        if ("location" in matched && !locationAvailable) {
            fail("Location matches require a location projection.", "$parent.matched_fields")
        }
        val snippetValue = map["snippet"]
        if (primary == "title") {
            if (snippetValue != null) fail("Title matches cannot carry a snippet.", "$parent.snippet")
            return
        }
        val snippet = objectMap(snippetValue, "$parent.snippet")
        exact(snippet, SnippetFields, "$parent.snippet")
        if (enum(snippet, "field", "$parent.snippet", allowedOrder.filter { it != "title" }.toSet()) != primary) {
            fail("Snippet field must equal primary_field.", "$parent.snippet.field")
        }
        text(snippet, "text", "$parent.snippet", 1, 200)
        boolean(snippet, "prefix_truncated", "$parent.snippet")
        boolean(snippet, "suffix_truncated", "$parent.snippet")
    }

    private fun request(arguments: Any?, parent: String, validator: (Map<String, Any?>, String) -> Unit): V2JsonRequest {
        val map = normalizeObject(arguments, parent)
        validator(map, parent)
        return V2JsonRequest(map)
    }

    private fun normalizeObject(value: Any?, parent: String): Map<String, Any?> = try {
        NativeContractJsonCodec.normalizeMap(value)
    } catch (error: IllegalArgumentException) {
        throw NativeContractViolation("$parent must be an object.", parent, error)
    }

    private fun exact(map: Map<String, Any?>, fields: Set<String>, parent: String) {
        ContractValidators.rejectUnknownFields(map, fields, parent)
        fields.firstOrNull { !map.containsKey(it) }?.let { fail("$parent.$it is required.", "$parent.$it") }
    }

    private fun objectMap(value: Any?, parent: String): Map<String, Any?> {
        if (value !is Map<*, *>) fail("$parent must be an object.", parent)
        return buildMap {
            value.forEach { (key, item) ->
                if (key !is String) fail("$parent contains a non-string key.", parent)
                put(key, item)
            }
        }
    }

    private fun list(map: Map<String, Any?>, key: String, parent: String): List<Any?> =
        map[key] as? List<*> ?: fail("$parent.$key must be an array.", "$parent.$key")

    private fun objectList(map: Map<String, Any?>, key: String, parent: String, minimum: Int, maximum: Int): List<Map<String, Any?>> {
        val values = list(map, key, parent)
        if (values.size !in minimum..maximum) fail("$parent.$key size is out of range.", "$parent.$key")
        return values.mapIndexed { index, item -> objectMap(item, "$parent.$key[$index]") }
    }

    private fun stringList(
        map: Map<String, Any?>,
        key: String,
        parent: String,
        minimum: Int,
        maximum: Int,
        maximumItemLength: Int? = null,
    ): List<String> {
        val values = list(map, key, parent)
        if (values.size !in minimum..maximum) fail("$parent.$key size is out of range.", "$parent.$key")
        return values.mapIndexed { index, item ->
            if (item !is String) fail("$parent.$key[$index] must be a string.", "$parent.$key[$index]")
            SearchTextContract.requireValidScalars(item, "$parent.$key[$index]")
            if (item.isEmpty() || (maximumItemLength != null && SearchTextContract.scalarCount(item) > maximumItemLength)) {
                fail("$parent.$key[$index] length is out of range.", "$parent.$key[$index]")
            }
            item
        }
    }

    private fun nullableStringList(
        map: Map<String, Any?>,
        key: String,
        parent: String,
        minimum: Int,
        maximum: Int,
        maximumItemLength: Int,
    ): List<String>? {
        if (!map.containsKey(key)) fail("$parent.$key is required.", "$parent.$key")
        if (map[key] == null) return null
        return stringList(map, key, parent, minimum, maximum, maximumItemLength)
    }

    private fun string(map: Map<String, Any?>, key: String, parent: String): String =
        map[key] as? String ?: fail("$parent.$key must be a string.", "$parent.$key")

    private fun text(map: Map<String, Any?>, key: String, parent: String, minimum: Int = 0, maximum: Int? = null): String {
        val value = string(map, key, parent)
        SearchTextContract.requireValidScalars(value, "$parent.$key")
        val count = SearchTextContract.scalarCount(value)
        if (count < minimum || (maximum != null && count > maximum)) fail("$parent.$key length is out of range.", "$parent.$key")
        return value
    }

    private fun nullableText(map: Map<String, Any?>, key: String, parent: String, minimum: Int = 0, maximum: Int? = null): String? {
        if (!map.containsKey(key)) fail("$parent.$key is required.", "$parent.$key")
        if (map[key] == null) return null
        return text(map, key, parent, minimum, maximum)
    }

    private fun boolean(map: Map<String, Any?>, key: String, parent: String): Boolean =
        map[key] as? Boolean ?: fail("$parent.$key must be boolean.", "$parent.$key")

    private fun enum(map: Map<String, Any?>, key: String, parent: String, allowed: Set<String>): String {
        val value = map[key]
        if (value !is String || value !in allowed) fail("$parent.$key has an unsupported enum value.", "$parent.$key")
        return value
    }

    private fun safeInteger(map: Map<String, Any?>, key: String, parent: String): Long =
        integer(map, key, parent, 0, MaximumSafeInteger)

    private fun integer(map: Map<String, Any?>, key: String, parent: String, minimum: Long, maximum: Long?): Long {
        val value = exactLong(map[key])
        if (value == null || value < minimum || (maximum != null && value > maximum)) {
            fail("$parent.$key must be an integer in range.", "$parent.$key")
        }
        return value
    }

    private fun nullableInteger(map: Map<String, Any?>, key: String, parent: String, minimum: Long, maximum: Long?): Long? {
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

    private fun localDate(map: Map<String, Any?>, key: String, parent: String): LocalDate {
        val value = string(map, key, parent)
        if (!DatePattern.matches(value)) fail("$parent.$key must use YYYY-MM-DD.", "$parent.$key")
        return try { LocalDate.parse(value) } catch (_: DateTimeException) {
            fail("$parent.$key must be a valid date.", "$parent.$key")
        }
    }

    private fun nullableDate(map: Map<String, Any?>, key: String, parent: String): LocalDate? {
        if (!map.containsKey(key)) fail("$parent.$key is required.", "$parent.$key")
        if (map[key] == null) return null
        return localDate(map, key, parent)
    }

    private fun utcInstant(map: Map<String, Any?>, key: String, parent: String): Instant {
        val value = string(map, key, parent)
        if (!UtcPattern.matches(value)) fail("$parent.$key must be a second-precision UTC instant.", "$parent.$key")
        return try { Instant.parse(value) } catch (_: DateTimeException) {
            fail("$parent.$key must be a valid UTC instant.", "$parent.$key")
        }
    }

    private fun nullableUtcInstant(map: Map<String, Any?>, key: String, parent: String): Instant? {
        if (!map.containsKey(key)) fail("$parent.$key is required.", "$parent.$key")
        if (map[key] == null) return null
        return utcInstant(map, key, parent)
    }

    private fun timezone(map: Map<String, Any?>, key: String, parent: String): String {
        val value = text(map, key, parent, 1, 255)
        return try {
            IanaTimezoneContract.require(value, "$parent.$key")
        } catch (error: NativeContractViolation) {
            fail(error.message ?: "Invalid timezone.", "$parent.$key", NativeErrorCodes.TimezoneIdInvalid, error)
        }
    }

    private fun nullableCursor(map: Map<String, Any?>, key: String, parent: String, response: Boolean = false): String? {
        if (!map.containsKey(key)) fail("$parent.$key is required.", "$parent.$key")
        val value = map[key] ?: return null
        if (value !is String || !CursorPattern.matches(value)) {
            fail(
                "$parent.$key is malformed.",
                "$parent.$key",
                if (response) NativeErrorCodes.ContractValidationFailed else NativeErrorCodes.SearchCursorInvalid,
            )
        }
        return value
    }

    private fun snapshotToken(map: Map<String, Any?>, key: String, parent: String): String {
        val value = string(map, key, parent)
        if (!SnapshotPattern.matches(value)) fail("$parent.$key is malformed.", "$parent.$key")
        return value
    }

    private fun uuid(map: Map<String, Any?>, key: String, parent: String): String {
        val value = string(map, key, parent)
        if (!UuidPattern.matches(value)) fail("$parent.$key must be a canonical UUID.", "$parent.$key")
        return value
    }

    private fun nullableUuid(map: Map<String, Any?>, key: String, parent: String): String? {
        if (!map.containsKey(key)) fail("$parent.$key is required.", "$parent.$key")
        if (map[key] == null) return null
        return uuid(map, key, parent)
    }

    private fun requireUnique(values: List<String>, field: String, errorCode: String) {
        if (values.toSet().size != values.size) fail("$field must contain unique values.", field, errorCode)
    }

    private fun requireCanonicalValues(values: List<String>, order: List<String>, field: String, errorCode: String) {
        requireUnique(values, field, errorCode)
        if (values != order.filter { it in values }) fail("$field must use canonical order.", field, errorCode)
    }

    private fun fail(
        message: String,
        field: String,
        errorCode: String = NativeErrorCodes.ContractValidationFailed,
        cause: Throwable? = null,
    ): Nothing = throw NativeContractViolation(message, field, cause, errorCode)

    private const val QueryRequest = "SearchQueryRequest"
    private const val QueryResponse = "SearchQueryResponse"
    private const val ReplaceHistoryRequest = "ReplaceSearchHistoryRequest"
    private const val FixedPageSize = 20L
    const val MaximumHistoryItems = 20
    const val MaximumSafeInteger = 9_007_199_254_740_991L

    private val TargetOrder = listOf("event", "habit", "anniversary")
    private val TargetValues = TargetOrder.toSet()
    private val SortValues = setOf("relevance", "occur_time", "updated_at")
    private val EventStatuses = setOf("pending", "in_progress", "overdue", "completed", "skipped")
    private val HabitStatuses = setOf("upcoming", "active", "completed", "ended_early")
    private val AnniversaryRelations = setOf("remaining", "elapsed", "today")
    private val EventMatchOrder = listOf("title", "content", "location", "category_name")
    private val HabitMatchOrder = listOf("title", "description", "category_name")
    private val AnniversaryMatchOrder = listOf("title", "note", "category_name")

    private val QueryRequestFields = setOf(
        "query_generation", "keyword", "timezone", "target_types", "date_from", "date_to_exclusive",
        "category_ids", "include_uncategorized", "include_completed", "sort_by", "sections",
    )
    private val SectionRequestFields = setOf("target_type", "page_size", "cursor")
    private val ReplaceHistoryRequestFields = setOf("expected_revision", "items")
    private val QueryResponseFields = setOf(
        "query_generation", "normalized_keyword", "timezone", "evaluated_at", "snapshot_token", "sections",
    )
    private val SectionResponseFields = setOf("target_type", "items", "total_count", "has_more", "next_cursor")
    private val HistoryResponseFields = setOf("revision", "items")
    private val CategoryFields = setOf("id", "name", "color", "icon")
    private val MatchFields = setOf("primary_field", "matched_fields", "snippet")
    private val SnippetFields = setOf("field", "text", "prefix_truncated", "suffix_truncated")
    private val EventFields = setOf(
        "target_type", "target_id", "title", "match", "category", "updated_at", "status", "is_all_day",
        "is_recurring", "occur_at", "occur_date", "location", "recurrence_revision", "occurrence_key",
    )
    private val HabitFields = setOf(
        "target_type", "target_id", "title", "match", "category", "updated_at", "lifecycle_status", "occur_date",
        "challenge_start_date", "challenge_end_date", "ended_date", "remaining_days", "target_count_hundredths", "unit",
    )
    private val AnniversaryFields = setOf(
        "target_type", "target_id", "title", "match", "category", "updated_at", "occurrence_key", "occur_date",
        "source_date", "is_repeating", "relation", "days", "years_elapsed",
    )
    private val DatePattern = Regex("^\\d{4}-\\d{2}-\\d{2}$")
    private val UtcPattern = Regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
    private val CursorPattern = Regex("^srchcur1\\.[A-Za-z0-9_-]{20,2048}$")
    private val SnapshotPattern = Regex("^srchsnap1\\.[A-Za-z0-9_-]{20,512}$")
    private val UuidPattern = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
    private val CategoryUuidPattern = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
    private val ColorPattern = Regex("^#[0-9A-F]{6}$")
}

/** Frozen Unicode whitespace and ASCII-only identity rules shared with local history repair. */
object SearchTextContract {
    fun requireQueryKeyword(value: String, field: String) {
        requireValidScalars(value, field, NativeErrorCodes.SearchQueryInvalid)
        requireSize(value, field, NativeErrorCodes.SearchQueryInvalid)
        val normalized = normalize(value)
        if (normalized.isEmpty()) throw NativeContractViolation("$field is empty after normalization.", field, errorCode = NativeErrorCodes.SearchQueryInvalid)
        requireSize(normalized, field, NativeErrorCodes.SearchQueryInvalid)
    }

    fun requireCanonicalNormalized(value: String, field: String) {
        requireValidScalars(value, field)
        requireSize(value, field)
        if (value.isEmpty() || normalize(value) != value) {
            throw NativeContractViolation("$field must be a canonical normalized keyword.", field)
        }
    }

    fun requireCanonicalHistory(values: List<String>, field: String) {
        if (values.size > SearchContracts.MaximumHistoryItems) {
            throw NativeContractViolation("$field exceeds the history limit.", field)
        }
        val identities = mutableSetOf<String>()
        values.forEachIndexed { index, value ->
            val itemField = "$field[$index]"
            requireCanonicalNormalized(value, itemField)
            if (!identities.add(asciiFold(value))) {
                throw NativeContractViolation("$field contains an ASCII-insensitive duplicate.", itemField)
            }
        }
    }

    fun normalize(value: String): String {
        val output = StringBuilder(value.length)
        var pendingSpace = false
        var index = 0
        while (index < value.length) {
            val codePoint = Character.codePointAt(value, index)
            index += Character.charCount(codePoint)
            if (codePoint in FrozenWhitespace) {
                if (output.isNotEmpty()) pendingSpace = true
            } else {
                if (pendingSpace) output.append(' ')
                output.appendCodePoint(codePoint)
                pendingSpace = false
            }
        }
        return output.toString()
    }

    fun asciiFold(value: String): String = buildString(value.length) {
        value.forEach { character -> append(if (character in 'A'..'Z') character + 32 else character) }
    }

    fun scalarCount(value: String): Int = value.codePointCount(0, value.length)

    fun utf8Length(value: String): Int {
        requireValidScalars(value, "SearchText")
        return try {
            Charsets.UTF_8.newEncoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .encode(java.nio.CharBuffer.wrap(value))
                .remaining()
        } catch (error: CharacterCodingException) {
            throw NativeContractViolation("SearchText contains malformed Unicode.", "SearchText", error)
        }
    }

    fun hasValidScalars(value: String): Boolean {
        var index = 0
        while (index < value.length) {
            val character = value[index]
            when {
                Character.isHighSurrogate(character) -> {
                    if (index + 1 >= value.length || !Character.isLowSurrogate(value[index + 1])) return false
                    index += 2
                }
                Character.isLowSurrogate(character) -> return false
                else -> index += 1
            }
        }
        return true
    }

    fun requireValidScalars(
        value: String,
        field: String,
        errorCode: String = NativeErrorCodes.ContractValidationFailed,
    ) {
        if (!hasValidScalars(value)) {
            throw NativeContractViolation("$field contains an isolated UTF-16 surrogate.", field, errorCode = errorCode)
        }
    }

    private fun requireSize(
        value: String,
        field: String,
        errorCode: String = NativeErrorCodes.ContractValidationFailed,
    ) {
        if (scalarCount(value) > MaximumScalars || utf8Length(value) > MaximumUtf8Bytes) {
            throw NativeContractViolation("$field exceeds the Search keyword limit.", field, errorCode = errorCode)
        }
    }

    private const val MaximumScalars = 128
    private const val MaximumUtf8Bytes = 512
    private val FrozenWhitespace = buildSet {
        addAll(0x0009..0x000D)
        add(0x0020)
        add(0x0085)
        add(0x00A0)
        add(0x1680)
        addAll(0x2000..0x200A)
        add(0x2028)
        add(0x2029)
        add(0x202F)
        add(0x205F)
        add(0x3000)
    }
}
