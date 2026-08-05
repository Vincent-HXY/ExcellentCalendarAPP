package com.excellentcalendar.excellent_calendar.bridge

import com.excellentcalendar.excellent_calendar.bridge.contract.NativeContractViolation
import com.excellentcalendar.excellent_calendar.bridge.contract.RuntimeTimezoneRequestContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.RuntimeTimezoneResponseContracts
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class RuntimeTimezoneContractsTest {
    @Test
    fun localWallTimeIsStrictAndDoesNotAcceptAnOffset() {
        val request = RuntimeTimezoneRequestContracts.resolveLocalDateTime(
            mapOf(
                "local_datetime" to "2026-03-29T01:30:00",
                "timezone" to "Europe/London",
            ),
        )
        assertEquals("2026-03-29T01:30:00", request.value["local_datetime"])

        assertThrows(NativeContractViolation::class.java) {
            RuntimeTimezoneRequestContracts.resolveLocalDateTime(
                mapOf(
                    "local_datetime" to "2026-03-29T01:30:00Z",
                    "timezone" to "Europe/London",
                ),
            )
        }
        assertThrows(NativeContractViolation::class.java) {
            RuntimeTimezoneRequestContracts.resolveLocalDateTime(
                mapOf(
                    "local_datetime" to "2026-02-30T01:30:00",
                    "timezone" to "Europe/London",
                ),
            )
        }
    }

    @Test
    fun localizationBatchEnforcesBoundsWholeSecondsAndUnknownFields() {
        RuntimeTimezoneRequestContracts.localizeInstants(
            mapOf(
                "timezone" to "Europe/London",
                "instants" to listOf("2026-03-29T01:00:00Z", "2026-03-29T01:00:00Z"),
            ),
        )

        listOf(
            emptyList<String>(),
            List(401) { "2026-03-29T01:00:00Z" },
            listOf("2026-03-29T01:00:00.000Z"),
        ).forEach { instants ->
            assertThrows(NativeContractViolation::class.java) {
                RuntimeTimezoneRequestContracts.localizeInstants(
                    mapOf("timezone" to "Europe/London", "instants" to instants),
                )
            }
        }

        assertThrows(NativeContractViolation::class.java) {
            RuntimeTimezoneRequestContracts.localizeInstants(
                mapOf(
                    "timezone" to "Europe/London",
                    "instants" to listOf("2026-03-29T01:00:00Z"),
                    "unknown" to true,
                ),
            )
        }
    }

    @Test
    fun responsesMustCorrespondToTheRequestAndPreserveBatchOrder() {
        RuntimeTimezoneResponseContracts.resolveLocalDateTime(
            data = mapOf(
                "requested_local_datetime" to "2026-03-29T01:30:00",
                "resolved_local_datetime" to "2026-03-29T02:00:00",
                "utc_instant" to "2026-03-29T01:00:00Z",
                "timezone" to "Europe/London",
                "resolution" to "gap_shifted",
            ),
            expectedLocalDateTime = "2026-03-29T01:30:00",
            expectedTimezone = "Europe/London",
        )

        assertThrows(NativeContractViolation::class.java) {
            RuntimeTimezoneResponseContracts.localizeInstants(
                data = mapOf(
                    "timezone" to "Europe/London",
                    "items" to listOf(
                        mapOf(
                            "instant" to "2026-03-29T01:00:00Z",
                            "local_datetime" to "2026-03-29T02:00:00",
                        ),
                        mapOf(
                            "instant" to "2026-03-29T00:30:00Z",
                            "local_datetime" to "2026-03-29T00:30:00",
                        ),
                    ),
                ),
                expectedTimezone = "Europe/London",
                expectedInstants = listOf("2026-03-29T00:30:00Z", "2026-03-29T01:00:00Z"),
            )
        }
    }
}
