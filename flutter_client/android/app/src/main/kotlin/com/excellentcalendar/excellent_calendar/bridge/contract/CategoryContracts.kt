package com.excellentcalendar.excellent_calendar.bridge.contract

internal object CategoryRequestContracts {
    private val createFields = setOf(
        "name",
        "description",
        "color",
        "icon",
        "sort_order",
    )

    fun list(arguments: Any?): V2JsonRequest = V2ContractPrimitives.request(
        arguments,
        "CategoryListRequest",
    ) { map ->
        V2ContractPrimitives.requireExactFields(map, emptySet(), "CategoryListRequest")
    }

    fun create(arguments: Any?): V2JsonRequest = V2ContractPrimitives.request(
        arguments,
        "CreateCategoryRequest",
    ) { map ->
        V2ContractPrimitives.requireExactFields(map, createFields, "CreateCategoryRequest")
        CategoryContractValidation.text(
            map,
            "name",
            "CreateCategoryRequest",
            40,
            nullable = false,
            requireNonBlank = true,
        )
        CategoryContractValidation.text(
            map,
            "description",
            "CreateCategoryRequest",
            200,
            nullable = true,
        )
        // Optional text is forwarded unchanged; the C++ writer owns blank-to-null normalization.
        CategoryContractValidation.color(map, "color", "CreateCategoryRequest", nullable = false, canonical = false)
        CategoryContractValidation.text(map, "icon", "CreateCategoryRequest", 64, nullable = true)
        CategoryContractValidation.sortOrder(map, "sort_order", "CreateCategoryRequest", nullable = true)
    }
}

internal object CategoryResponseContracts {
    fun validate(data: Any?, parent: String = "CategoryResponse"): Map<String, Any?> =
        CategoryContractValidation.category(data, parent)

    fun active(data: Any?, parent: String): Map<String, Any?> = validate(data, parent).also { category ->
        if (category["deleted_at"] != null) {
            throw NativeContractViolation(
                "$parent must be an active Category.",
                "$parent.deleted_at",
            )
        }
    }

    fun created(data: Any?) {
        val category = active(data, "CategoryResponse")
        if (category["color"] == null) {
            throw NativeContractViolation(
                "Created Category must be active and carry its required color.",
                "CategoryResponse",
            )
        }
    }

    fun list(data: Any?) {
        val map = CategoryContractValidation.objectMap(data, "CategoryListResponse")
        V2ContractPrimitives.requireExactFields(map, setOf("items"), "CategoryListResponse")
        val rawItems = map["items"] as? List<*> ?: throw NativeContractViolation(
            "CategoryListResponse.items must be an array.",
            "CategoryListResponse.items",
        )
        val items = rawItems.mapIndexed { index, item ->
            active(item, "CategoryListResponse.items[$index]")
        }
        val ids = items.map { it.getValue("id") as String }
        if (ids.toSet().size != ids.size) {
            throw NativeContractViolation(
                "CategoryListResponse contains duplicate Category IDs.",
                "CategoryListResponse.items",
            )
        }
        if (items.zipWithNext().any { (first, second) ->
                CategoryContractValidation.compare(first, second) > 0
            }
        ) {
            throw NativeContractViolation(
                "CategoryListResponse.items are not in Contract order.",
                "CategoryListResponse.items",
            )
        }
    }
}

private object CategoryContractValidation {
    private val uuidV4Pattern = Regex(
        "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
    )
    private val inputColorPattern = Regex("^#[0-9A-Fa-f]{6}$")
    private val canonicalColorPattern = Regex("^#[0-9A-F]{6}$")
    private val utcSecondPattern = Regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
    private val responseFields = setOf(
        "id",
        "name",
        "description",
        "color",
        "icon",
        "sort_order",
        "created_at",
        "updated_at",
        "deleted_at",
    )

    fun category(value: Any?, parent: String): Map<String, Any?> {
        val map = objectMap(value, parent)
        V2ContractPrimitives.requireExactFields(map, responseFields, parent)
        val id = map["id"] as? String
        if (id == null || !uuidV4Pattern.matches(id)) {
            fail("$parent.id must be a canonical lowercase UUIDv4.", "$parent.id")
        }
        text(map, "name", parent, 40, nullable = false, requireNonBlank = true)
        text(map, "description", parent, 200, nullable = true)
        color(map, "color", parent, nullable = true, canonical = true)
        text(map, "icon", parent, 64, nullable = true)
        sortOrder(map, "sort_order", parent, nullable = true)
        utcSecond(map, "created_at", parent, nullable = false)
        utcSecond(map, "updated_at", parent, nullable = false)
        utcSecond(map, "deleted_at", parent, nullable = true)
        if ((map.getValue("updated_at") as String) < (map.getValue("created_at") as String)) {
            fail("$parent.updated_at cannot precede created_at.", "$parent.updated_at")
        }
        return map
    }

    fun compare(first: Map<String, Any?>, second: Map<String, Any?>): Int {
        val firstOrder = integer(first["sort_order"])
        val secondOrder = integer(second["sort_order"])
        if (firstOrder != secondOrder) {
            if (firstOrder == null) return 1
            if (secondOrder == null) return -1
            return firstOrder.compareTo(secondOrder)
        }
        val createdComparison = (first.getValue("created_at") as String)
            .compareTo(second.getValue("created_at") as String)
        if (createdComparison != 0) return createdComparison
        return (first.getValue("id") as String).compareTo(second.getValue("id") as String)
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

    fun text(
        map: Map<String, Any?>,
        key: String,
        parent: String,
        maximumLength: Int,
        nullable: Boolean,
        requireNonBlank: Boolean = false,
    ) {
        val value = map[key]
        if (value == null && nullable) return
        val invalid = value !is String ||
            value.isEmpty() ||
            value.codePointCount(0, value.length) > maximumLength ||
            (requireNonBlank && value.isBlank())
        if (invalid) {
            fail(
                if (requireNonBlank) {
                    "$parent.$key must be non-blank and at most $maximumLength characters."
                } else {
                    "$parent.$key must be non-empty and at most $maximumLength characters."
                },
                "$parent.$key",
            )
        }
    }

    fun color(
        map: Map<String, Any?>,
        key: String,
        parent: String,
        nullable: Boolean,
        canonical: Boolean,
    ) {
        val value = map[key]
        if (value == null && nullable) return
        val pattern = if (canonical) canonicalColorPattern else inputColorPattern
        if (value !is String || !pattern.matches(value)) {
            fail("$parent.$key must use #RRGGBB.", "$parent.$key")
        }
    }

    fun sortOrder(
        map: Map<String, Any?>,
        key: String,
        parent: String,
        nullable: Boolean,
    ) {
        val value = map[key]
        if (value == null && nullable) return
        val number = integer(value)
        if (number == null || number !in 0..MaximumSortOrder) {
            fail(
                "$parent.$key must be null or an integer in 0..$MaximumSortOrder.",
                "$parent.$key",
            )
        }
    }

    private fun utcSecond(
        map: Map<String, Any?>,
        key: String,
        parent: String,
        nullable: Boolean,
    ) {
        val value = map[key]
        if (value == null && nullable) return
        if (value !is String || !utcSecondPattern.matches(value)) {
            fail("$parent.$key must be a whole-second UTC instant.", "$parent.$key")
        }
        val date = value.substring(0, 10)
        if (!isValidDate(date) ||
            value.substring(11, 13).toInt() !in 0..23 ||
            value.substring(14, 16).toInt() !in 0..59 ||
            value.substring(17, 19).toInt() !in 0..59
        ) {
            fail("$parent.$key must be a valid UTC instant.", "$parent.$key")
        }
    }

    private fun isValidDate(value: String): Boolean {
        val year = value.substring(0, 4).toInt()
        val month = value.substring(5, 7).toInt()
        val day = value.substring(8, 10).toInt()
        if (year < 1 || month !in 1..12) return false
        val maximumDay = when (month) {
            2 -> if (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) 29 else 28
            4, 6, 9, 11 -> 30
            else -> 31
        }
        return day in 1..maximumDay
    }

    private fun integer(value: Any?): Long? = when (value) {
        is Int -> value.toLong()
        is Long -> value
        else -> null
    }

    private fun fail(message: String, field: String): Nothing =
        throw NativeContractViolation(message, field)

    private const val MaximumSortOrder = 9_007_199_254_740_991L
}
