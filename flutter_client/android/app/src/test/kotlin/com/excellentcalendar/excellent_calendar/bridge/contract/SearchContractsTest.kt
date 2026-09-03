package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class SearchContractsTest {
    @Test
    fun allRevisionTwoFixturesArePresentAndDirectlyConsumableByTheKotlinSuite() {
        val manifest = fixture("manifest.json")
        assertEquals(2L, (manifest["fixture_version"] as Number).toLong())
        @Suppress("UNCHECKED_CAST")
        val cases = manifest["cases"] as List<Map<String, Any?>>
        assertEquals(31, cases.size)
        cases.forEach { case ->
            val instance = case["instance"] as String
            fixture(instance)
        }
    }

    @Test
    fun revisionTwoRequestAndResponseFixturesMapExactly() {
        val request = SearchContracts.queryRequest(fixture("query_three_sections.valid.json"))
        SearchContracts.queryResponse(fixture("query_response_three_types.valid.json"), request.value)

        assertEquals("项目 MEETING", SearchTextContract.normalize(request.value["keyword"] as String))
        assertEquals(
            listOf("event", "habit", "anniversary"),
            request.value["target_types"],
        )
    }

    @Test
    fun semanticRequestFixturesReturnFrozenErrorsBeforeNative() {
        val cases = listOf(
            "query_reversed_range.semantic_invalid.json" to NativeErrorCodes.SearchQueryInvalid,
            "query_blank.semantic_invalid.json" to NativeErrorCodes.SearchQueryInvalid,
            "query_section_mismatch.semantic_invalid.json" to NativeErrorCodes.SearchQueryInvalid,
            "query_multi_cursor.semantic_invalid.json" to NativeErrorCodes.SearchQueryInvalid,
            "query_target_order.semantic_invalid.json" to NativeErrorCodes.SearchQueryInvalid,
            "query_bad_cursor.invalid.json" to NativeErrorCodes.SearchCursorInvalid,
        )
        cases.forEach { (name, expectedCode) ->
            val error = assertThrows(NativeContractViolation::class.java) {
                SearchContracts.queryRequest(fixture(name))
            }
            assertEquals("fixture=$name", expectedCode, error.errorCode)
        }
    }

    @Test
    fun UnicodeScalarAndFixedPageSizeBoundariesAreStrict() {
        val base = fixture("query_three_sections.valid.json")
        val isolated = base.toMutableMap().also { it["keyword"] = "bad\uD800" }
        val tooLong = base.toMutableMap().also { it["keyword"] = "😀".repeat(129) }
        val pageSize = base.toMutableMap().also { map ->
            @Suppress("UNCHECKED_CAST")
            map["sections"] = (map["sections"] as List<Map<String, Any?>>).map { it + ("page_size" to 21) }
        }

        listOf(isolated, tooLong).forEach {
            assertEquals(
                NativeErrorCodes.SearchQueryInvalid,
                assertThrows(NativeContractViolation::class.java) { SearchContracts.queryRequest(it) }.errorCode,
            )
        }
        assertThrows(NativeContractViolation::class.java) { SearchContracts.queryRequest(pageSize) }
    }

    @Test
    fun malformedTypedResponsesFailClosedInsteadOfSynthesizingEmptySections() {
        val request = SearchContracts.queryRequest(fixture("query_three_sections.valid.json"))
        val missing = fixture("query_response_missing_sections.semantic_invalid.json")
        val wrongCategory = fixture("query_response_three_types.valid.json").toMutableMap().also { response ->
            @Suppress("UNCHECKED_CAST")
            val sections = (response["sections"] as List<Map<String, Any?>>).map { section ->
                if (section["target_type"] != "event") section else section.toMutableMap().also { mutableSection ->
                    @Suppress("UNCHECKED_CAST")
                    mutableSection["items"] = (section["items"] as List<Map<String, Any?>>).map { item ->
                        item.toMutableMap().also { mutableItem ->
                            @Suppress("UNCHECKED_CAST")
                            val match = (mutableItem["match"] as Map<String, Any?>).toMutableMap()
                            match["primary_field"] = "category_name"
                            match["matched_fields"] = listOf("category_name")
                            match["snippet"] = linkedMapOf(
                                "field" to "category_name",
                                "text" to "项目",
                                "prefix_truncated" to false,
                                "suffix_truncated" to false,
                            )
                            mutableItem["match"] = match
                            mutableItem["category"] = null
                        }
                    }
                }
            }
            response["sections"] = sections
        }

        assertThrows(NativeContractViolation::class.java) {
            SearchContracts.queryResponse(missing, request.value)
        }
        assertThrows(NativeContractViolation::class.java) {
            SearchContracts.queryResponse(wrongCategory, request.value)
        }
    }

    @Test
    fun historyFixturesEnforceCanonicalOrderAndAsciiInsensitiveIdentity() {
        SearchContracts.historyResponse(fixture("history.valid.json"))
        SearchContracts.replaceHistoryRequest(fixture("history_clear.valid.json"))

        assertThrows(NativeContractViolation::class.java) {
            SearchContracts.historyResponse(fixture("history_case_duplicate.semantic_invalid.json"))
        }
        assertThrows(NativeContractViolation::class.java) {
            SearchContracts.replaceHistoryRequest(fixture("history_noncanonical.semantic_invalid.json"))
        }
    }

    @Test
    fun frozenWhitespaceAndAsciiOnlyFoldMatchGoldenVectors() {
        val vectors = fixture("normalization.golden.json")["vectors"] as List<*>
        vectors.forEach { value ->
            @Suppress("UNCHECKED_CAST")
            val vector = value as Map<String, Any?>
            val normalized = SearchTextContract.normalize(vector["raw"] as String)
            assertEquals(vector["normalized"], normalized)
            @Suppress("UNCHECKED_CAST")
            val expected = vector["comparison_tokens"] as List<String>
            assertEquals(expected, normalized.split(' ').filter(String::isNotEmpty).map(SearchTextContract::asciiFold))
        }
    }

    private fun fixture(name: String): Map<String, Any?> {
        val directory = fixtureDirectories.firstOrNull(File::isDirectory)
            ?: error("Cannot locate frozen Search fixtures from ${System.getProperty("user.dir")}")
        return NativeContractJsonCodec.decodeObject(File(directory, name).readText(Charsets.UTF_8))
    }

    companion object {
        private val fixtureDirectories = listOf(
            File("../../../contracts/fixtures/search"),
            File("../../contracts/fixtures/search"),
            File("../contracts/fixtures/search"),
            File("contracts/fixtures/search"),
        )
    }
}
