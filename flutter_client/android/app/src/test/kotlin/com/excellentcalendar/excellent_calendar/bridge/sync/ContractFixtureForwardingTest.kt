package com.excellentcalendar.excellent_calendar.bridge.sync

import java.io.File
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ContractFixtureForwardingTest {
    @Test fun frozenJcsVectorsAreRejectedOrForwardedWithoutRebuildingTheirPayload() {
        val fixture = JSONObject(File(contractRoot(), "fixtures/sync/v1/jcs_boundary_vectors.json").readText())
        val cases = fixture.getJSONArray("cases")
        assertTrue(cases.length() >= 50)
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val raw = case.getString("input_json")
            if (case.getBoolean("expected_error")) {
                failure("HTTP_ENVELOPE_INVALID") { StrictBoundary.requireJson(raw.toByteArray()) }
            } else {
                val forwarded = try { StrictBoundary.requireJson(raw.toByteArray()) }
                catch (error: SyncLocalFailure) { throw AssertionError(case.getString("id"), error) }
                assertEquals(case.getString("id"), raw, forwarded)
            }
        }
        // This proves lexical validation and unchanged transport, not a Kotlin JCS encoder.
    }
}
