package com.excellentcalendar.excellent_calendar.bridge

import com.excellentcalendar.excellent_calendar.bridge.contract.CategoryRequestContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.CategoryResponseContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeContractViolation
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class CategoryContractsTest {
    @Test
    fun validRequestsPreserveTheExactSnakeCaseWireShape() {
        val list = CategoryRequestContracts.list(emptyMap<String, Any?>())
        val createArguments = linkedMapOf<String, Any?>(
            "name" to "工作",
            "description" to null,
            "color" to "#39AFBD",
            "icon" to null,
            "sort_order" to MaximumSortOrder,
        )
        val create = CategoryRequestContracts.create(createArguments)

        assertEquals(emptyMap<String, Any?>(), list.value)
        assertEquals(createArguments, create.value)
        assertEquals(
            setOf("name", "description", "color", "icon", "sort_order"),
            create.value.keys,
        )
    }

    @Test
    fun explicitNullIsValidButAMissingNullableFieldIsMalformed() {
        CategoryRequestContracts.create(createRequest(description = null))

        val missingDescription = createRequest().toMutableMap().also {
            it.remove("description")
        }
        assertThrows(NativeContractViolation::class.java) {
            CategoryRequestContracts.create(missingDescription)
        }
    }

    @Test
    fun optionalTextIsForwardedForCppNormalizationInsteadOfBeingRewritten() {
        val arguments = createRequest(description = " ").toMutableMap().also {
            it["name"] = "  工作  "
            it["color"] = "#39afbd"
            it["icon"] = " "
        }

        val parsed = CategoryRequestContracts.create(arguments)

        assertEquals("  工作  ", parsed.value["name"])
        assertEquals(" ", parsed.value["description"])
        assertEquals("#39afbd", parsed.value["color"])
        assertEquals(" ", parsed.value["icon"])
    }

    @Test
    fun sortOrderAcceptsTheSafeIntegerMaximumAndRejectsTheFirstValueAboveIt() {
        val maximumRequest = createRequest().toMutableMap().also {
            it["sort_order"] = MaximumSortOrder
        }
        val maximumResponse = categoryResponse(sortOrder = MaximumSortOrder)

        CategoryRequestContracts.create(maximumRequest)
        CategoryResponseContracts.created(maximumResponse)

        val aboveMaximumRequest = createRequest().toMutableMap().also {
            it["sort_order"] = FirstInvalidSortOrder
        }
        val aboveMaximumResponse = categoryResponse(sortOrder = FirstInvalidSortOrder)
        assertThrows(NativeContractViolation::class.java) {
            CategoryRequestContracts.create(aboveMaximumRequest)
        }
        assertThrows(NativeContractViolation::class.java) {
            CategoryResponseContracts.created(aboveMaximumResponse)
        }
    }

    @Test
    fun createRejectsWrongFieldTypesEmptyNameAndUnknownFields() {
        val invalidRequests = listOf(
            createRequest().toMutableMap().also { it["name"] = 7 },
            createRequest().toMutableMap().also { it["name"] = "   " },
            createRequest().toMutableMap().also { it["description"] = 7 },
            createRequest().toMutableMap().also { it["color"] = null },
            createRequest().toMutableMap().also { it["icon"] = false },
            createRequest().toMutableMap().also { it["sort_order"] = 1.5 },
            createRequest().toMutableMap().also { it["displayName"] = "parallel field" },
        )

        invalidRequests.forEach { request ->
            assertThrows(NativeContractViolation::class.java) {
                CategoryRequestContracts.create(request)
            }
        }
    }

    @Test
    fun nonObjectMethodChannelPayloadsAreRejectedExplicitly() {
        listOf<Any?>(null, "{}", listOf("name"), 7).forEach { arguments ->
            assertThrows(NativeContractViolation::class.java) {
                CategoryRequestContracts.create(arguments)
            }
        }
        assertThrows(NativeContractViolation::class.java) {
            CategoryRequestContracts.list(null)
        }
    }

    @Test
    fun validCreatedAndListResponsesMatchTheFlutterDtoShape() {
        val category = categoryResponse()

        CategoryResponseContracts.created(category)
        CategoryResponseContracts.list(linkedMapOf("items" to listOf(category)))
        CategoryResponseContracts.list(linkedMapOf("items" to emptyList<Any?>()))
    }

    @Test
    fun responseNullableFieldsMustBePresentAndCreatedCategoryMustBeActive() {
        val missingNullable = categoryResponse().toMutableMap().also {
            it.remove("deleted_at")
        }
        val nullColor = categoryResponse().toMutableMap().also {
            it["color"] = null
        }

        assertThrows(NativeContractViolation::class.java) {
            CategoryResponseContracts.created(missingNullable)
        }
        assertThrows(NativeContractViolation::class.java) {
            CategoryResponseContracts.created(nullColor)
        }
        CategoryResponseContracts.list(linkedMapOf("items" to listOf(nullColor)))
    }

    @Test
    fun malformedAndUnknownResponseFieldsAreRejected() {
        val invalidCategories = listOf(
            categoryResponse().toMutableMap().also { it["id"] = 7 },
            categoryResponse().toMutableMap().also { it["color"] = "#39afbd" },
            categoryResponse().toMutableMap().also { it["sort_order"] = true },
            categoryResponse().toMutableMap().also { it["created_at"] = "2026-02-30T08:00:00Z" },
            categoryResponse().toMutableMap().also { it["unexpected"] = true },
        )

        invalidCategories.forEach { category ->
            assertThrows(NativeContractViolation::class.java) {
                CategoryResponseContracts.list(linkedMapOf("items" to listOf(category)))
            }
        }
        assertThrows(NativeContractViolation::class.java) {
            CategoryResponseContracts.list(linkedMapOf("items" to "not-an-array"))
        }
        assertThrows(NativeContractViolation::class.java) {
            CategoryResponseContracts.created(null)
        }
    }

    private fun createRequest(description: String? = "工作计划"): Map<String, Any?> = linkedMapOf(
        "name" to "工作",
        "description" to description,
        "color" to "#39AFBD",
        "icon" to null,
        "sort_order" to null,
    )

    private fun categoryResponse(sortOrder: Any? = 1): Map<String, Any?> = linkedMapOf(
        "id" to "40000000-0000-4000-8000-000000000001",
        "name" to "工作",
        "description" to "工作计划",
        "color" to "#39AFBD",
        "icon" to null,
        "sort_order" to sortOrder,
        "created_at" to "2026-08-10T08:00:00Z",
        "updated_at" to "2026-08-10T08:00:00Z",
        "deleted_at" to null,
    )

    private companion object {
        const val MaximumSortOrder = 9_007_199_254_740_991L
        const val FirstInvalidSortOrder = 9_007_199_254_740_992L
    }
}
