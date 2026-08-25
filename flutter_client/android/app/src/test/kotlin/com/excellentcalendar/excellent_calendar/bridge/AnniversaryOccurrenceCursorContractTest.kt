package com.excellentcalendar.excellent_calendar.bridge

import com.excellentcalendar.excellent_calendar.bridge.contract.AnniversaryRequestContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.AnniversaryResponseContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeContractViolation
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class AnniversaryOccurrenceCursorContractTest {
    @Test
    fun cppGoldenCursorPassesResponseValidationAndCanBeUsedForTheNextPageRequest() {
        val response = linkedMapOf<String, Any?>(
            "items" to listOf(occurrence()),
            "has_more" to true,
            "next_cursor" to CppGoldenCursor,
        )

        AnniversaryResponseContracts.occurrences(response)
        val request = AnniversaryRequestContracts.listOccurrences(
            occurrenceRequest(response.getValue("next_cursor")),
        )

        assertEquals(CppGoldenCursor, request.value["cursor"])
    }

    @Test
    fun legacyDottedGenerationCursorFailsBothResponseAndNextPageRequestValidation() {
        assertThrows(NativeContractViolation::class.java) {
            AnniversaryResponseContracts.occurrences(
                linkedMapOf(
                    "items" to listOf(occurrence()),
                    "has_more" to true,
                    "next_cursor" to LegacyDottedGenerationCursor,
                ),
            )
        }
        assertThrows(NativeContractViolation::class.java) {
            AnniversaryRequestContracts.listOccurrences(occurrenceRequest(LegacyDottedGenerationCursor))
        }
    }

    private fun occurrenceRequest(cursor: Any?): Map<String, Any?> = linkedMapOf(
        "range_start_date" to "2026-08-01",
        "range_end_date" to "2027-09-05",
        "timezone" to "Asia/Shanghai",
        "category_ids" to emptyList<String>(),
        "importance" to emptyList<String>(),
        "cursor" to cursor,
        "page_size" to 50,
    )

    private fun occurrence(): Map<String, Any?> = linkedMapOf(
        "anniversary_id" to "22222222-2222-4222-8222-222222222222",
        "occurrence_key" to "11111111-1111-4111-8111-111111111111",
        "occurrence_date" to "2026-09-01",
        "source_date" to "2020-09-01",
        "title" to "C++ cursor fixture",
        "calendar_type" to "solar",
        "is_repeating" to true,
        "years_elapsed" to 6,
        "category_id" to null,
        "importance" to null,
        "has_active_reminders" to false,
        "reminder_count" to 0,
    )

    private companion object {
        const val CppGoldenCursor =
            "annocc1.60f0df06-830c-52d2-a659-e8848aa200cd_3-1-1_55ed42b28911a7e6"
        const val LegacyDottedGenerationCursor =
            "annocc1.60f0df06-830c-52d2-a659-e8848aa200cd_3.1.1_55ed42b28911a7e6"
    }
}
