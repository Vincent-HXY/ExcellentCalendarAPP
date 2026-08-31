package com.excellentcalendar.excellent_calendar.bridge.native

import android.content.Context
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import java.io.File
import java.time.LocalDate
import java.time.ZoneId

/** Production-factory smoke for the real Habit JNI surface and SQLite v5 runtime. */
internal object HabitJniSmokeRunner {
    fun run(context: Context): String {
        check(NativeContractRuntimeProfile.current == NativeContractProfile.V2)
        val bridge = AndroidNativeBridgeFactory.create(context)
        check(bridge is JniNativeCalendarCoreBridge) {
            "AndroidNativeBridgeFactory did not return the production JNI bridge"
        }

        val runtime = successData(
            bridge.initializeRuntime(
                CalendarCoreV2RuntimeRequestProvider(context.applicationContext).createRequestJson(),
            ),
            "runtime.initialize",
        )
        check(runtime["initialized"] == true) { "Calendar Core runtime was not initialized" }
        check((runtime["storage_format_version"] as? Number)?.toInt() == StorageVersion) {
            "Calendar Core runtime did not negotiate SQLite v$StorageVersion: $runtime"
        }
        check(runtime["tzdb_version"] == BundledTzdbExtractor.Version) {
            "Calendar Core runtime returned the wrong TZDB version: $runtime"
        }
        val storageDirectory = CalendarCoreV2StorageDirectoryResolver.resolve(context.filesDir)
        check(File(storageDirectory, DatabaseFileName).isFile) {
            "SQLite v$StorageVersion database was not materialized"
        }

        verifyAllHabitExports(bridge)

        val today = LocalDate.now(ZoneId.of(Timezone))
        val startDate = today.plusDays(1)
        val endDate = startDate.plusDays(6)
        var habitId: String? = null
        var expectedUpdatedAt: String? = null
        try {
            val created = successData(
                bridge.createHabit(
                    json(
                        linkedMapOf(
                            "title" to MarkerTitle,
                            "description" to "真实 JNI 与 SQLite v5",
                            "category_id" to null,
                            "recurrence" to linkedMapOf(
                                "frequency" to "daily",
                                "interval" to 1,
                                "timezone_mode" to "follow_device",
                            ),
                            "target_count_hundredths" to null,
                            "unit" to null,
                            "start_date" to startDate.toString(),
                            "end_date" to endDate.toString(),
                            "reminder" to linkedMapOf(
                                "is_enabled" to false,
                                "local_time" to null,
                                "timezone_mode" to "follow_device",
                                "method" to "popup",
                            ),
                            "timezone" to Timezone,
                        ),
                    ),
                ),
                "habit.create",
            )
            check(created["data_saved"] == true) { "habit.create did not commit data" }
            val createdHabit = habitFromMutation(created, "habit.create")
            habitId = createdHabit["id"] as? String ?: error("habit.create returned no Habit id")
            expectedUpdatedAt = createdHabit["updated_at"] as? String
                ?: error("habit.create returned no optimistic timestamp")
            check(createdHabit["title"] == MarkerTitle) {
                "Habit Unicode title changed across Kotlin/JNI/C++: $createdHabit"
            }

            val detail = successData(
                bridge.getHabitDetail(
                    json(
                        linkedMapOf(
                            "id" to habitId,
                            "timezone" to Timezone,
                            "history_page_size" to 7,
                        ),
                    ),
                ),
                "habit.get_detail",
            )
            check(objectMap(detail["habit"], "habit.get_detail.habit")["id"] == habitId) {
                "habit.get_detail did not recover the created SQLite row"
            }

            val listed = successData(
                bridge.listHabits(json(linkedMapOf("timezone" to Timezone))),
                "habit.list",
            )
            val items = listed["items"] as? List<*>
                ?: error("habit.list returned no items")
            check(items.any { item ->
                val summary = item as? Map<*, *> ?: return@any false
                val habit = summary["habit"] as? Map<*, *> ?: return@any false
                habit["id"] == habitId
            }) { "habit.list did not recover the created SQLite row" }

            val deleted = successData(
                bridge.deleteHabit(
                    json(
                        linkedMapOf(
                            "id" to habitId,
                            "expected_updated_at" to expectedUpdatedAt,
                            "timezone" to Timezone,
                        ),
                    ),
                ),
                "habit.delete",
            )
            check(deleted["data_saved"] == true && deleted["habit_id"] == habitId) {
                "habit.delete did not commit the cleanup tombstone: $deleted"
            }
            habitId = null
            expectedUpdatedAt = null
        } finally {
            val cleanupId = habitId
            val cleanupTimestamp = expectedUpdatedAt
            if (cleanupId != null && cleanupTimestamp != null) {
                runCatching {
                    bridge.deleteHabit(
                        json(
                            linkedMapOf(
                                "id" to cleanupId,
                                "expected_updated_at" to cleanupTimestamp,
                                "timezone" to Timezone,
                            ),
                        ),
                    )
                }
            }
        }

        return "PASS production Habit JNI: 11/11 exports, Unicode create/get/list/delete, SQLite v$StorageVersion"
    }

    private fun verifyAllHabitExports(bridge: NativeHabitBridge) {
        val calls = linkedMapOf<String, (String) -> String>(
            "habit.create" to bridge::createHabit,
            "habit.update" to bridge::updateHabit,
            "habit.list" to bridge::listHabits,
            "habit.get_detail" to bridge::getHabitDetail,
            "habit.end" to bridge::endHabit,
            "habit.delete" to bridge::deleteHabit,
            "habit.check_in" to bridge::checkInHabit,
            "habit.clear_check_in" to bridge::clearHabitCheckIn,
            "habit.list_daily_statuses" to bridge::listHabitDailyStatuses,
            "habit.set_reminder" to bridge::setHabitReminder,
            "habit.reconcile_reminders" to bridge::reconcileHabitReminders,
        )
        calls.forEach { (operation, call) ->
            val result = NativeContractJsonCodec.decodeObject(call("["))
            verifyEnvelope(result, operation, expectedOk = false)
            val error = result["error"] as? Map<*, *>
                ?: error("$operation returned no NativeError")
            check(error["code"] == NativeErrorCodes.ContractValidationFailed) {
                "$operation did not execute its real C++ boundary: $result"
            }
        }
    }

    private fun successData(json: String, operation: String): Map<String, Any?> {
        val result = NativeContractJsonCodec.decodeObject(json)
        verifyEnvelope(result, operation, expectedOk = true)
        return objectMap(result["data"], "$operation.data")
    }

    private fun verifyEnvelope(
        result: Map<String, Any?>,
        operation: String,
        expectedOk: Boolean,
    ) {
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

    private fun habitFromMutation(data: Map<String, Any?>, operation: String): Map<String, Any?> {
        val detail = objectMap(data["detail"], "$operation.detail")
        return objectMap(detail["habit"], "$operation.detail.habit")
    }

    @Suppress("UNCHECKED_CAST")
    private fun objectMap(value: Any?, parent: String): Map<String, Any?> =
        value as? Map<String, Any?> ?: error("$parent must be an object")

    private fun json(value: Map<String, Any?>): String = NativeContractJsonCodec.encodeObject(value)

    private const val StorageVersion = 5
    private const val DatabaseFileName = "calendar_core.sqlite3"
    private const val Timezone = "Asia/Shanghai"
    private const val MarkerTitle = "JNI 习惯🗓️"
}
