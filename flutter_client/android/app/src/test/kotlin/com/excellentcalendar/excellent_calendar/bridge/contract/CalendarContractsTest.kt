package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class CalendarContractsTest {
    @Test
    fun frozenRequestFixturesUseCalendarSpecificSemanticErrors() {
        CalendarContracts.rangeSummaryRequest(fixture("range_request_42_days.valid.json"))
        CalendarContracts.listDayItemsRequest(fixture("list_day_items_first_page.valid.json"))

        assertError(NativeErrorCodes.CalendarRangeTooLarge) {
            CalendarContracts.rangeSummaryRequest(fixture("range_request_43_days.semantic_invalid.json"))
        }
        assertError(NativeErrorCodes.CalendarRangeInvalid) {
            CalendarContracts.rangeSummaryRequest(fixture("range_request_reversed.semantic_invalid.json"))
        }
        assertError(NativeErrorCodes.CalendarCursorInvalid) {
            CalendarContracts.listDayItemsRequest(fixture("list_day_items_bad_cursor.invalid.json"))
        }
        assertError(NativeErrorCodes.CalendarSnapshotInvalid) {
            CalendarContracts.listDayItemsRequest(fixture("list_day_items_bad_snapshot.invalid.json"))
        }
    }

    @Test
    fun frozenRangeAndThreeTypedPageFixturesPassStrictKotlinValidation() {
        CalendarContracts.rangeSummaryResponse(fixture("range_summary_empty_day.valid.json"))
        CalendarContracts.rangeSummaryResponse(fixture("range_summary_three_types.valid.json"))
        CalendarContracts.dayItemPage(fixture("event_page.valid.json"))
        CalendarContracts.dayItemPage(fixture("habit_page.valid.json"))
        CalendarContracts.dayItemPage(fixture("anniversary_page.valid.json"))
    }

    @Test
    fun responseShapeRejectsGapsNonTerminalEmptyPagesAndWrongSectionItems() {
        assertContractFailure {
            CalendarContracts.rangeSummaryResponse(fixture("range_summary_gap.semantic_invalid.json"))
        }
        assertContractFailure {
            CalendarContracts.dayItemPage(fixture("nonterminal_empty.invalid.json"))
        }

        val wrongSection = fixture("event_page.valid.json").toMutableMap().also {
            it["section"] = "habit"
        }
        assertContractFailure { CalendarContracts.dayItemPage(wrongSection) }
    }

    @Test
    fun requestBoundaryRejectsNullExtraUnknownEnumFractionalPageAndInvalidTimezone() {
        val valid = fixture("list_day_items_first_page.valid.json")
        val invalid = listOf(
            valid.toMutableMap().also { it["date"] = null },
            valid.toMutableMap().also { it["unexpected"] = true },
            valid.toMutableMap().also { it["section"] = "task" },
            valid.toMutableMap().also { it["page_size"] = 20.0 },
        )
        invalid.forEach { request -> assertContractFailure { CalendarContracts.listDayItemsRequest(request) } }

        assertError(NativeErrorCodes.TimezoneIdInvalid) {
            CalendarContracts.listDayItemsRequest(valid.toMutableMap().also { it["timezone"] = "Mars/Olympus" })
        }
    }

    @Test
    fun responseMustEchoRequestIdentityAndKeepItemConditionalFieldsConsistent() {
        val request = fixture("list_day_items_first_page.valid.json")
        val page = fixture("event_page.valid.json")
        CalendarContracts.dayItemPage(page, request)

        assertContractFailure {
            CalendarContracts.dayItemPage(page.toMutableMap().also { it["snapshot_token"] = snapshot("Z") }, request)
        }

        @Suppress("UNCHECKED_CAST")
        val items = page["items"] as List<Map<String, Any?>>
        val malformedItem = items.first().toMutableMap().also { it["display_local_time"] = "09:00" }
        val malformedPage = page.toMutableMap().also { it["items"] = listOf(malformedItem) }
        assertContractFailure { CalendarContracts.dayItemPage(malformedPage) }
    }

    @Test
    fun habitQuantityStatusMustMatchProgressAndPreserveOverCompletion() {
        val page = fixture("habit_page.valid.json")
        @Suppress("UNCHECKED_CAST")
        val items = page["items"] as List<Map<String, Any?>>

        val partialAtTarget = items.first().toMutableMap().also {
            it["completed_count_hundredths"] = it["target_count_hundredths"]
        }
        assertContractFailure {
            CalendarContracts.dayItemPage(page.toMutableMap().also {
                it["items"] = listOf(partialAtTarget, items[1])
            })
        }

        val doneBelowTarget = items[1].toMutableMap().also {
            it["completed_count_hundredths"] = 2_999L
            it["target_count_hundredths"] = 3_000L
            it["unit"] = "minutes"
        }
        assertContractFailure {
            CalendarContracts.dayItemPage(page.toMutableMap().also {
                it["items"] = listOf(items[0], doneBelowTarget)
            })
        }

        val doneAboveTarget = doneBelowTarget.toMutableMap().also {
            it["completed_count_hundredths"] = 3_500L
        }
        CalendarContracts.dayItemPage(page.toMutableMap().also {
            it["items"] = listOf(items[0], doneAboveTarget)
        })
    }

    private fun assertError(expected: String, block: () -> Unit) {
        val error = assertThrows(NativeContractViolation::class.java, block)
        assertEquals(expected, error.errorCode)
    }

    private fun assertContractFailure(block: () -> Unit) =
        assertError(NativeErrorCodes.ContractValidationFailed, block)

    private fun fixture(name: String): Map<String, Any?> {
        val directory = fixtureDirectories.firstOrNull(File::isDirectory)
            ?: error("Cannot locate frozen Calendar fixtures from ${System.getProperty("user.dir")}")
        return NativeContractJsonCodec.decodeObject(File(directory, name).readText(Charsets.UTF_8))
    }

    private fun snapshot(character: String): String = "calsnap1." + character.repeat(20)

    companion object {
        private val fixtureDirectories = listOf(
            File("../../../contracts/fixtures/calendar"),
            File("../../contracts/fixtures/calendar"),
            File("../contracts/fixtures/calendar"),
            File("contracts/fixtures/calendar"),
        )
    }
}
