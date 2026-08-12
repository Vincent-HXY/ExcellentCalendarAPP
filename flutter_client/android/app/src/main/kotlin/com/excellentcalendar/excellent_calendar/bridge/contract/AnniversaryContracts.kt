package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec

object AnniversaryRequestContracts {
    private val anniversaryFields = setOf(
        "title",
        "date",
        "calendar_type",
        "category_id",
        "recurrence",
        "note",
        "importance",
        "timezone",
    )

    fun create(arguments: Any?): V2JsonRequest = request(arguments, "CreateAnniversaryRequest") { map ->
        AnniversaryContractValidation.requireExactFields(map, anniversaryFields, "CreateAnniversaryRequest")
        AnniversaryContractValidation.anniversaryWriteFields(map, "CreateAnniversaryRequest")
    }

    fun update(arguments: Any?): V2JsonRequest = request(arguments, "UpdateAnniversaryRequest") { map ->
        val fields = anniversaryFields + "id"
        AnniversaryContractValidation.requireExactFields(map, fields, "UpdateAnniversaryRequest")
        AnniversaryContractValidation.uuid(map, "id", "UpdateAnniversaryRequest")
        AnniversaryContractValidation.anniversaryWriteFields(map, "UpdateAnniversaryRequest")
    }

    fun delete(arguments: Any?): V2JsonRequest = request(arguments, "DeleteAnniversaryRequest") { map ->
        AnniversaryContractValidation.requireExactFields(map, setOf("id"), "DeleteAnniversaryRequest")
        AnniversaryContractValidation.uuid(map, "id", "DeleteAnniversaryRequest")
    }

    fun detail(arguments: Any?): V2JsonRequest = request(arguments, "GetAnniversaryDetailRequest") { map ->
        AnniversaryContractValidation.requireExactFields(map, setOf("id", "timezone"), "GetAnniversaryDetailRequest")
        AnniversaryContractValidation.uuid(map, "id", "GetAnniversaryDetailRequest")
        AnniversaryContractValidation.nonEmptyString(map, "timezone", "GetAnniversaryDetailRequest")
    }

    fun list(arguments: Any?): V2JsonRequest = request(arguments, "ListAnniversariesRequest") { map ->
        val allowed = setOf("timezone", "category_ids", "importance", "pagination", "sort_by", "sort_direction")
        ContractValidators.rejectUnknownFields(map, allowed, "ListAnniversariesRequest")
        AnniversaryContractValidation.nonEmptyString(map, "timezone", "ListAnniversariesRequest")
        AnniversaryContractValidation.optionalUuidArray(map, "category_ids", "ListAnniversariesRequest")
        AnniversaryContractValidation.optionalEnumArray(
            map,
            "importance",
            "ListAnniversariesRequest",
            ContractEnums.Importance,
        )
        AnniversaryContractValidation.optionalPagination(map, "pagination", "ListAnniversariesRequest")
        AnniversaryContractValidation.optionalEnum(
            map,
            "sort_by",
            "ListAnniversariesRequest",
            setOf("target_occurrence_date", "countdown_days"),
        )
        AnniversaryContractValidation.optionalEnum(
            map,
            "sort_direction",
            "ListAnniversariesRequest",
            ContractEnums.SortDirection,
        )
    }

    fun previewCountdown(arguments: Any?): V2JsonRequest =
        request(arguments, "PreviewAnniversaryCountdownRequest") { map ->
            AnniversaryContractValidation.requireExactFields(
                map,
                setOf("date", "calendar_type", "recurrence", "timezone"),
                "PreviewAnniversaryCountdownRequest",
            )
            AnniversaryContractValidation.localDate(map, "date", "PreviewAnniversaryCountdownRequest")
            AnniversaryContractValidation.enum(
                map,
                "calendar_type",
                "PreviewAnniversaryCountdownRequest",
                setOf("solar", "lunar"),
            )
            AnniversaryContractValidation.recurrence(map, "PreviewAnniversaryCountdownRequest")
            AnniversaryContractValidation.nonEmptyString(map, "timezone", "PreviewAnniversaryCountdownRequest")
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
    fun detail(data: Any?) {
        val map = AnniversaryContractValidation.objectMap(data, "AnniversaryDetailResponse")
        AnniversaryContractValidation.requireExactFields(
            map,
            setOf("anniversary", "recurrence", "countdown"),
            "AnniversaryDetailResponse",
        )
        val anniversary = AnniversaryContractValidation.anniversaryResponse(
            map["anniversary"],
            "AnniversaryDetailResponse.anniversary",
        )
        if (anniversary["calendar_type"] != "solar" || anniversary["deleted_at"] != null) {
            throw NativeContractViolation(
                "AnniversaryDetailResponse must contain an active solar Anniversary.",
                "AnniversaryDetailResponse.anniversary",
            )
        }
        val recurrence = map["recurrence"]?.let {
            AnniversaryContractValidation.recurrenceResponse(it, "AnniversaryDetailResponse.recurrence")
        }
        if ((anniversary["recurrence_id"] == null) != (recurrence == null) ||
            (recurrence != null && anniversary["recurrence_id"] != recurrence["recurrence_id"])
        ) {
            throw NativeContractViolation(
                "AnniversaryDetailResponse recurrence identity is inconsistent.",
                "AnniversaryDetailResponse.recurrence",
            )
        }
        AnniversaryContractValidation.countdown(map["countdown"], "AnniversaryDetailResponse.countdown")
    }

    fun deleted(data: Any?) {
        val anniversary = AnniversaryContractValidation.anniversaryResponse(data, "DeletedAnniversaryResponse")
        if (anniversary["deleted_at"] == null) {
            throw NativeContractViolation(
                "DeletedAnniversaryResponse.deleted_at must be a UTC instant.",
                "DeletedAnniversaryResponse.deleted_at",
            )
        }
    }

    fun list(data: Any?) {
        val map = AnniversaryContractValidation.objectMap(data, "AnniversaryListResponse")
        AnniversaryContractValidation.requireExactFields(
            map,
            setOf("items", "pagination"),
            "AnniversaryListResponse",
        )
        val items = map["items"] as? List<*> ?: throw NativeContractViolation(
            "AnniversaryListResponse.items must be an array.",
            "AnniversaryListResponse.items",
        )
        items.forEachIndexed { index, item ->
            val parent = "AnniversaryListResponse.items[$index]"
            val summary = AnniversaryContractValidation.objectMap(item, parent)
            AnniversaryContractValidation.requireExactFields(summary, setOf("anniversary", "countdown"), parent)
            val anniversary = AnniversaryContractValidation.anniversaryResponse(
                summary["anniversary"],
                "$parent.anniversary",
            )
            if (anniversary["calendar_type"] != "solar" || anniversary["deleted_at"] != null) {
                throw NativeContractViolation(
                    "$parent must contain an active solar Anniversary.",
                    "$parent.anniversary",
                )
            }
            AnniversaryContractValidation.countdown(summary["countdown"], "$parent.countdown")
        }
        AnniversaryContractValidation.paginationResponse(map["pagination"], "AnniversaryListResponse.pagination")
    }

    fun countdown(data: Any?) {
        AnniversaryContractValidation.countdown(data, "AnniversaryCountdownResponse")
    }
}

private object AnniversaryContractValidation {
    private val uuidPattern = Regex(
        "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$",
    )
    private val localDatePattern = Regex("^\\d{4}-\\d{2}-\\d{2}$")
    private val utcSecondPattern = Regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
    private val anniversaryResponseFields = setOf(
        "id",
        "title",
        "date",
        "calendar_type",
        "category_id",
        "recurrence_id",
        "note",
        "importance",
        "created_at",
        "updated_at",
        "deleted_at",
    )

    fun anniversaryWriteFields(map: Map<String, Any?>, parent: String) {
        nonEmptyString(map, "title", parent)
        localDate(map, "date", parent)
        enum(map, "calendar_type", parent, setOf("solar", "lunar"))
        nullableUuid(map, "category_id", parent)
        recurrence(map, parent)
        nullableString(map, "note", parent)
        enum(map, "importance", parent, ContractEnums.Importance)
        nonEmptyString(map, "timezone", parent)
    }

    fun recurrence(map: Map<String, Any?>, parent: String) {
        if (!map.containsKey("recurrence")) {
            fail("$parent.recurrence is required.", "$parent.recurrence")
        }
        val value = map["recurrence"] ?: return
        val recurrence = objectMap(value, "$parent.recurrence")
        requireExactFields(recurrence, setOf("frequency", "interval"), "$parent.recurrence")
        if (recurrence["frequency"] != "yearly") {
            fail("$parent.recurrence.frequency must be yearly.", "$parent.recurrence.frequency")
        }
        if (integer(recurrence["interval"]) != 1L) {
            fail("$parent.recurrence.interval must be 1.", "$parent.recurrence.interval")
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
        utcSecond(map, "created_at", parent, nullable = false)
        utcSecond(map, "updated_at", parent, nullable = false)
        utcSecond(map, "deleted_at", parent, nullable = true)
        return map
    }

    fun recurrenceResponse(value: Any?, parent: String): Map<String, Any?> {
        val map = objectMap(value, parent)
        requireExactFields(map, setOf("recurrence_id", "frequency", "interval"), parent)
        uuid(map, "recurrence_id", parent)
        if (map["frequency"] != "yearly" || integer(map["interval"]) != 1L) {
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
        val days = integer(map["days"])
        if (days == null || days < 0 || (relation == "today" && days != 0L) || (relation != "today" && days < 1L)) {
            fail("$parent.days is inconsistent with relation.", "$parent.days")
        }
        localDate(map, "target_occurrence_date", parent)
        val isoWeekday = integer(map["iso_weekday"])
        if (isoWeekday == null || isoWeekday !in 1L..7L) {
            fail("$parent.iso_weekday must be between 1 and 7.", "$parent.iso_weekday")
        }
        nonEmptyString(map, "timezone", parent)
        utcSecond(map, "calculated_at", parent, nullable = false)
    }

    fun paginationResponse(value: Any?, parent: String) {
        val map = objectMap(value, parent)
        requireExactFields(map, setOf("total", "page", "page_size", "has_more", "next_cursor"), parent)
        val total = integer(map["total"])
        if (map["total"] != null && (total == null || total < 0)) fail("$parent.total is invalid.", "$parent.total")
        val page = integer(map["page"])
        if (map["page"] != null && (page == null || page < 1)) fail("$parent.page is invalid.", "$parent.page")
        val pageSize = integer(map["page_size"])
        if (pageSize == null || pageSize !in 1L..200L) fail("$parent.page_size is invalid.", "$parent.page_size")
        if (map["has_more"] !is Boolean) fail("$parent.has_more must be boolean.", "$parent.has_more")
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

    fun optionalUuidArray(map: Map<String, Any?>, key: String, parent: String) {
        if (!map.containsKey(key)) return
        val values = map[key] as? List<*> ?: fail("$parent.$key must be an array.", "$parent.$key")
        if (values.isEmpty()) fail("$parent.$key must not be empty.", "$parent.$key")
        val strings = values.mapIndexed { index, value ->
            val string = value as? String ?: fail("$parent.$key[$index] must be a UUID.", "$parent.$key[$index]")
            validateUuid(string, "$parent.$key[$index]")
            string
        }
        if (strings.toSet().size != strings.size) fail("$parent.$key must contain unique values.", "$parent.$key")
    }

    fun optionalEnumArray(
        map: Map<String, Any?>,
        key: String,
        parent: String,
        allowed: Set<String>,
    ) {
        if (!map.containsKey(key)) return
        val values = map[key] as? List<*> ?: fail("$parent.$key must be an array.", "$parent.$key")
        if (values.isEmpty()) fail("$parent.$key must not be empty.", "$parent.$key")
        if (values.any { it !is String || it !in allowed }) fail("$parent.$key contains an unsupported value.", "$parent.$key")
        if (values.toSet().size != values.size) fail("$parent.$key must contain unique values.", "$parent.$key")
    }

    fun optionalEnum(map: Map<String, Any?>, key: String, parent: String, allowed: Set<String>) {
        if (!map.containsKey(key)) return
        val value = map[key]
        if (value != null && (value !is String || value !in allowed)) {
            fail("$parent.$key has an unsupported enum value.", "$parent.$key")
        }
    }

    fun requireExactFields(map: Map<String, Any?>, fields: Set<String>, parent: String) {
        ContractValidators.rejectUnknownFields(map, fields, parent)
        val missing = fields.firstOrNull { !map.containsKey(it) }
        if (missing != null) fail("$parent.$missing is required.", "$parent.$missing")
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

    fun uuid(map: Map<String, Any?>, key: String, parent: String) {
        val value = map[key] as? String ?: fail("$parent.$key must be a UUID.", "$parent.$key")
        validateUuid(value, "$parent.$key")
    }

    fun nullableUuid(map: Map<String, Any?>, key: String, parent: String) {
        if (!map.containsKey(key)) fail("$parent.$key is required.", "$parent.$key")
        val value = map[key] ?: return
        if (value !is String) fail("$parent.$key must be a UUID or null.", "$parent.$key")
        validateUuid(value, "$parent.$key")
    }

    fun localDate(map: Map<String, Any?>, key: String, parent: String) {
        val value = map[key] as? String ?: fail("$parent.$key must be a date.", "$parent.$key")
        if (!localDatePattern.matches(value)) fail("$parent.$key must use YYYY-MM-DD.", "$parent.$key")
        if (!isValidLocalDate(value)) fail("$parent.$key must be a valid date.", "$parent.$key")
    }

    fun nonEmptyString(map: Map<String, Any?>, key: String, parent: String) {
        val value = map[key]
        if (value !is String || value.isEmpty()) fail("$parent.$key must be a non-empty string.", "$parent.$key")
    }

    fun nullableString(map: Map<String, Any?>, key: String, parent: String) {
        if (!map.containsKey(key)) fail("$parent.$key is required.", "$parent.$key")
        if (map[key] != null && map[key] !is String) fail("$parent.$key must be a string or null.", "$parent.$key")
    }

    fun enum(map: Map<String, Any?>, key: String, parent: String, allowed: Set<String>) {
        val value = map[key]
        if (value !is String || value !in allowed) fail("$parent.$key has an unsupported enum value.", "$parent.$key")
    }

    private fun utcSecond(map: Map<String, Any?>, key: String, parent: String, nullable: Boolean) {
        if (!map.containsKey(key)) fail("$parent.$key is required.", "$parent.$key")
        val value = map[key]
        if (value == null && nullable) return
        if (value !is String || !utcSecondPattern.matches(value)) {
            fail("$parent.$key must be a whole-second UTC instant.", "$parent.$key")
        }
        if (!isValidLocalDate(value.substring(0, 10)) ||
            value.substring(11, 13).toInt() !in 0..23 ||
            value.substring(14, 16).toInt() !in 0..59 ||
            value.substring(17, 19).toInt() !in 0..59
        ) {
            fail("$parent.$key must be a valid UTC instant.", "$parent.$key")
        }
    }

    private fun isValidLocalDate(value: String): Boolean {
        if (!localDatePattern.matches(value)) return false
        val year = value.substring(0, 4).toInt()
        val month = value.substring(5, 7).toInt()
        val day = value.substring(8, 10).toInt()
        if (year < 1 || month !in 1..12) return false
        val maximumDay = when (month) {
            2 -> if (isLeapYear(year)) 29 else 28
            4, 6, 9, 11 -> 30
            else -> 31
        }
        return day in 1..maximumDay
    }

    private fun isLeapYear(year: Int): Boolean =
        year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)

    private fun optionalIntegerRange(
        map: Map<String, Any?>,
        key: String,
        parent: String,
        minimum: Long,
        maximum: Long?,
    ) {
        if (!map.containsKey(key) || map[key] == null) return
        val value = integer(map[key])
        if (value == null || value < minimum || (maximum != null && value > maximum)) {
            fail("$parent.$key is out of range.", "$parent.$key")
        }
    }

    private fun optionalNullableString(map: Map<String, Any?>, key: String, parent: String) {
        if (!map.containsKey(key) || map[key] == null) return
        if (map[key] !is String) fail("$parent.$key must be a string or null.", "$parent.$key")
    }

    private fun validateUuid(value: String, field: String) {
        if (!uuidPattern.matches(value)) fail("$field must be a UUID.", field)
    }

    private fun integer(value: Any?): Long? = when (value) {
        is Int -> value.toLong()
        is Long -> value
        else -> null
    }

    private fun fail(message: String, field: String): Nothing = throw NativeContractViolation(message, field)
}
