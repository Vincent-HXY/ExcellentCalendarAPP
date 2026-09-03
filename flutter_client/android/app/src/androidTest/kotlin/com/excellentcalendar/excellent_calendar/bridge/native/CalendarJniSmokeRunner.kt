package com.excellentcalendar.excellent_calendar.bridge.native

import android.content.Context
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.CalendarContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import java.time.LocalDate
import java.time.ZoneId

/** Read-only production-factory smoke for both Calendar View JNI endpoints. */
internal object CalendarJniSmokeRunner {
    fun run(context: Context): String {
        check(NativeContractRuntimeProfile.current == NativeContractProfile.V2)
        val bridge = AndroidNativeBridgeFactory.create(context)
        check(bridge is JniNativeCalendarCoreBridge) {
            "AndroidNativeBridgeFactory did not return the production JNI bridge"
        }

        verifyFailure(
            bridge.calendarRangeSummary("["),
            "calendar.range_summary malformed JSON",
            NativeErrorCodes.ContractValidationFailed,
        )
        verifyFailure(
            bridge.calendarRangeSummary(
                json(
                    linkedMapOf(
                        "range_start_date" to "2026-08-31",
                        "range_end_date" to "2026-09-01",
                        "timezone" to "Asia/上海🗓️",
                    ),
                ),
            ),
            "calendar.range_summary Unicode invalid timezone",
            NativeErrorCodes.TimezoneIdInvalid,
        )

        val timezone = "Asia/Shanghai"
        val selectedDate = LocalDate.now(ZoneId.of(timezone))
        val rangeRequest = linkedMapOf<String, Any?>(
            "range_start_date" to selectedDate.minusDays(3).toString(),
            "range_end_date" to selectedDate.plusDays(4).toString(),
            "timezone" to timezone,
        )
        val rangeData = successData(
            bridge.calendarRangeSummary(json(rangeRequest)),
            "calendar.range_summary",
        )
        CalendarContracts.rangeSummaryResponse(rangeData, rangeRequest)
        val snapshot = rangeData["snapshot_token"] as? String
            ?: error("calendar.range_summary returned no snapshot_token")

        val itemCounts = linkedMapOf<String, Int>()
        listOf("event", "habit", "anniversary").forEach { section ->
            val request = linkedMapOf<String, Any?>(
                "date" to selectedDate.toString(),
                "timezone" to timezone,
                "section" to section,
                "snapshot_token" to snapshot,
                "cursor" to null,
                "page_size" to 100,
            )
            val data = successData(
                bridge.calendarListDayItems(json(request)),
                "calendar.list_day_items[$section]",
            )
            CalendarContracts.dayItemPage(data, request)
            itemCounts[section] = (data["items"] as List<*>).size
        }

        val oversizedCursorRequest = linkedMapOf<String, Any?>(
            "date" to selectedDate.toString(),
            "timezone" to timezone,
            "section" to "event",
            "snapshot_token" to snapshot,
            "cursor" to "calcur1.${"A".repeat(3000)}",
            "page_size" to 20,
        )
        verifyFailure(
            bridge.calendarListDayItems(json(oversizedCursorRequest)),
            "calendar.list_day_items oversized cursor",
            NativeErrorCodes.CalendarCursorInvalid,
        )

        return "PASS production Calendar JNI: 2/2 exports, 7-day snapshot, " +
            "three typed sections=$itemCounts, Unicode/large-cursor failures"
    }

    private fun successData(json: String, operation: String): Map<String, Any?> {
        val result = NativeContractJsonCodec.decodeObject(json)
        verifyEnvelope(result, operation, expectedOk = true)
        @Suppress("UNCHECKED_CAST")
        return result["data"] as? Map<String, Any?>
            ?: error("$operation returned no object data")
    }

    private fun verifyFailure(json: String, operation: String, expectedCode: String) {
        val result = NativeContractJsonCodec.decodeObject(json)
        verifyEnvelope(result, operation, expectedOk = false)
        val error = result["error"] as? Map<*, *> ?: error("$operation returned no NativeError")
        check(error["code"] == expectedCode) { "$operation returned the wrong error: $error" }
    }

    private fun verifyEnvelope(result: Map<String, Any?>, operation: String, expectedOk: Boolean) {
        check(result.keys == setOf("ok", "data", "error", "contract_version", "request_id")) {
            "$operation returned a non-exact NativeResult envelope: ${result.keys}"
        }
        check(result["ok"] == expectedOk) { "$operation returned the wrong outcome: $result" }
        check((result["contract_version"] as? Number)?.toInt() == 2) {
            "$operation returned the wrong Contract version: $result"
        }
        check(result["request_id"] is String) { "$operation returned no request_id" }
        if (expectedOk) {
            check(result["data"] != null && result["error"] == null) { "$operation failed: $result" }
        } else {
            check(result["data"] == null && result["error"] != null) {
                "$operation returned a malformed failure envelope: $result"
            }
        }
    }

    private fun json(value: Map<String, Any?>): String = NativeContractJsonCodec.encodeObject(value)
}
