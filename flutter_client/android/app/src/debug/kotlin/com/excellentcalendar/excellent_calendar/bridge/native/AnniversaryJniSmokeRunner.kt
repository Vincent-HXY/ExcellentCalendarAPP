package com.excellentcalendar.excellent_calendar.bridge.native

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.runtime.AndroidDeviceTimezoneProvider
import java.io.File
import java.util.UUID

internal object AnniversaryJniSmokeRunner {
    private const val SmokeTitlePrefix = "JNI smoke anniversary"

    fun run(context: Context): String {
        val storageDirectory = CalendarCoreV2StorageDirectoryResolver.resolve(
            context.filesDir,
        )
        val bridge = AndroidNativeBridgeFactory.create(context)
        cleanupOrphanedSmokeAnniversaries(bridge, storageDirectory)
        val create = NativeContractJsonCodec.decodeObject(
            bridge.createAnniversary(
                NativeContractJsonCodec.encodeObject(
                    linkedMapOf(
                        "title" to SmokeTitlePrefix,
                        "date" to "2020-02-29",
                        "calendar_type" to "solar",
                        "category_id" to null,
                        "recurrence" to linkedMapOf(
                            "frequency" to "yearly",
                            "interval" to 1,
                        ),
                        "note" to null,
                        "importance" to "important_noturgent",
                        "timezone" to "Asia/Shanghai",
                        "reminder_plan" to linkedMapOf(
                            "reminders_enabled" to true,
                            "templates" to listOf(
                                linkedMapOf(
                                    "advance_days" to 1,
                                    "local_time" to "09:30",
                                    "method" to "popup",
                                    "is_enabled" to true,
                                ),
                            ),
                        ),
                    ),
                ),
            ),
        )
        check(create["ok"] == true && create["error"] == null) {
            "anniversary.create failed: $create"
        }
        @Suppress("UNCHECKED_CAST")
        val createdData = create["data"] as? Map<String, Any?>
            ?: error("anniversary.create returned no detail data")
        @Suppress("UNCHECKED_CAST")
        val createdAnniversary = createdData["anniversary"] as? Map<String, Any?>
            ?: error("anniversary.create returned no Anniversary")
        val anniversaryId = createdAnniversary["id"] as? String
            ?: error("anniversary.create returned no id")
        val expectedUpdatedAt = createdAnniversary["updated_at"] as? String
            ?: error("anniversary.create returned no updated_at")

        val updated = decode(
            bridge.updateAnniversary(
                encode(
                    linkedMapOf(
                        "id" to anniversaryId,
                        "expected_updated_at" to expectedUpdatedAt,
                        "title" to "JNI smoke anniversary updated",
                        "date" to "2020-02-29",
                        "calendar_type" to "solar",
                        "category_id" to null,
                        "recurrence" to linkedMapOf(
                            "frequency" to "yearly",
                            "interval" to 1,
                        ),
                        "note" to null,
                        "importance" to "important_noturgent",
                        "timezone" to "Asia/Shanghai",
                        "reminder_plan" to linkedMapOf(
                            "reminders_enabled" to true,
                            "templates" to listOf(
                                linkedMapOf(
                                    "advance_days" to 0,
                                    "local_time" to "10:00",
                                    "method" to "popup",
                                    "is_enabled" to true,
                                ),
                            ),
                        ),
                    ),
                ),
            ),
        )
        check(updated["ok"] == true && updated["error"] == null) {
            "anniversary.update failed: $updated"
        }

        val detail = NativeContractJsonCodec.decodeObject(
            bridge.getAnniversaryDetail(
                NativeContractJsonCodec.encodeObject(
                    linkedMapOf(
                        "id" to anniversaryId,
                        "timezone" to "Asia/Shanghai",
                    ),
                ),
            ),
        )
        check(detail["ok"] == true && detail["error"] == null) {
            "anniversary.detail failed: $detail"
        }
        @Suppress("UNCHECKED_CAST")
        val detailData = detail["data"] as? Map<String, Any?>
            ?: error("anniversary.detail returned no detail data")
        @Suppress("UNCHECKED_CAST")
        val reloadedAnniversary = detailData["anniversary"] as? Map<String, Any?>
            ?: error("anniversary.detail returned no Anniversary")
        check(reloadedAnniversary["id"] == anniversaryId) {
            "anniversary.detail did not reload the created id"
        }

        val toggled = decode(
            bridge.setAnniversaryRemindersEnabled(
                encode(
                    linkedMapOf(
                        "id" to anniversaryId,
                        "reminders_enabled" to false,
                        "timezone" to "Asia/Shanghai",
                    ),
                ),
            ),
        )
        check(toggled["ok"] == true && toggled["error"] == null) {
            "anniversary.set_reminders_enabled failed: $toggled"
        }

        val occurrenceRequest = linkedMapOf<String, Any?>(
            "range_start_date" to "2024-01-01",
            "range_end_date" to "2025-01-01",
            "timezone" to "Asia/Shanghai",
            "category_ids" to emptyList<String>(),
            "importance" to emptyList<String>(),
            "cursor" to null,
            "page_size" to 50,
        )
        val occurrences = decode(bridge.listAnniversaryOccurrences(encode(occurrenceRequest)))
        check(occurrences["ok"] == true && occurrences["error"] == null) {
            "anniversary.list_occurrences failed: $occurrences"
        }

        val invalidOccurrences = decode(
            bridge.listAnniversaryOccurrences(
                encode(
                    LinkedHashMap(occurrenceRequest).apply {
                        this["range_end_date"] = "2025-02-05"
                    },
                ),
            ),
        )
        @Suppress("UNCHECKED_CAST")
        val invalidError = invalidOccurrences["error"] as? Map<String, Any?>
        check(
            invalidOccurrences["ok"] == false &&
                invalidError?.get("code") == "ANNIVERSARY_OCCURRENCE_RANGE_TOO_LARGE",
        ) {
            "anniversary.list_occurrences invalid fixture was not rejected: $invalidOccurrences"
        }

        val recovery = decode(
            bridge.planReminderRecovery(
                encode(
                    linkedMapOf(
                        "recovery_request_id" to UUID.randomUUID().toString(),
                        "trigger_source" to "app_start",
                        "timezone" to AndroidDeviceTimezoneProvider.currentTimezone(),
                    ),
                ),
            ),
        )
        check(recovery["ok"] == true && recovery["error"] == null) {
            "reminder.plan_recovery timezone round-trip failed: $recovery"
        }

        val invalidTimezoneRecovery = decode(
            bridge.planReminderRecovery(
                encode(
                    linkedMapOf(
                        "recovery_request_id" to UUID.randomUUID().toString(),
                        "trigger_source" to "app_start",
                        "timezone" to "Mars/Olympus",
                    ),
                ),
            ),
        )
        @Suppress("UNCHECKED_CAST")
        val invalidTimezoneError = invalidTimezoneRecovery["error"] as? Map<String, Any?>
        check(
            invalidTimezoneRecovery["ok"] == false &&
                invalidTimezoneError?.get("code") == "TIMEZONE_ID_INVALID",
        ) {
            "reminder.plan_recovery invalid timezone was not rejected: $invalidTimezoneRecovery"
        }

        val finalizeProbe = decode(
            bridge.finalizeReminderDelivery(
                encode(
                    linkedMapOf(
                        "delivery_attempt_id" to UUID.randomUUID().toString(),
                        "outcome" to "sent",
                        "failure_class" to null,
                        "error_code" to null,
                        "timezone" to AndroidDeviceTimezoneProvider.currentTimezone(),
                    ),
                ),
            ),
        )
        @Suppress("UNCHECKED_CAST")
        val finalizeProbeError = finalizeProbe["error"] as? Map<String, Any?>
        check(
            finalizeProbe["ok"] == false &&
                finalizeProbeError?.get("code") == "DELIVERY_ATTEMPT_INVALID",
        ) {
            "reminder.finalize_delivery timezone round-trip did not reach attempt lookup: $finalizeProbe"
        }
        checkSqliteStorage(storageDirectory)

        val deleted = NativeContractJsonCodec.decodeObject(
            bridge.deleteAnniversary(
                NativeContractJsonCodec.encodeObject(
                    linkedMapOf("id" to anniversaryId),
                ),
            ),
        )
        check(deleted["ok"] == true && deleted["error"] == null) {
            "anniversary.delete cleanup failed: $deleted"
        }
        return "PASS create->update->detail->toggle->occurrences(valid/invalid), " +
            "recovery/finalize timezone JNI round-trip id=$anniversaryId; soft-delete cleanup passed"
    }

    private fun encode(value: Map<String, Any?>): String = NativeContractJsonCodec.encodeObject(value)

    private fun decode(value: String): Map<String, Any?> = NativeContractJsonCodec.decodeObject(value)

    private fun cleanupOrphanedSmokeAnniversaries(
        bridge: NativeAnniversaryBridge,
        storageDirectory: File,
    ) {
        sqliteRecords(storageDirectory, "anniversaries").mapNotNull { record ->
            val title = record["title"] as? String ?: return@mapNotNull null
            val id = record["id"] as? String ?: return@mapNotNull null
            id.takeIf { title.startsWith(SmokeTitlePrefix) && record["deleted_at"] == null }
        }.forEach { id ->
            val deleted = decode(bridge.deleteAnniversary(encode(linkedMapOf("id" to id))))
            check(deleted["ok"] == true && deleted["error"] == null) {
                "orphaned Anniversary smoke cleanup failed: $deleted"
            }
        }
    }

    private fun checkSqliteStorage(storageDirectory: File) {
        val databaseFile = File(storageDirectory, "calendar_core.sqlite3")
        check(databaseFile.isFile) { "Calendar Core SQLite Storage v4 is missing" }
        SQLiteDatabase.openDatabase(
            databaseFile.absolutePath,
            null,
            SQLiteDatabase.OPEN_READONLY,
        ).use { database ->
            database.rawQuery("PRAGMA user_version", null).use { cursor ->
                check(cursor.moveToFirst() && cursor.getInt(0) == 4) {
                    "Calendar Core SQLite user_version is not 4"
                }
            }
            database.rawQuery("PRAGMA quick_check", null).use { cursor ->
                check(cursor.moveToFirst() && cursor.getString(0) == "ok") {
                    "Calendar Core SQLite quick_check failed"
                }
            }
            database.rawQuery(
                "SELECT COUNT(*) FROM schema_metadata " +
                    "WHERE key='storage_format_version' AND value='4'",
                null,
            ).use { cursor ->
                check(cursor.moveToFirst() && cursor.getInt(0) == 1) {
                    "Calendar Core SQLite metadata is invalid"
                }
            }
        }
        check(
            !File(storageDirectory, "workflow_transactions.json").exists() &&
                !File(storageDirectory, "anniversary_workflow_transactions.json").exists(),
        ) { "legacy workflow journals were not cleaned before SQLite migration" }
    }

    private fun sqliteRecords(
        storageDirectory: File,
        tableName: String,
    ): List<Map<String, Any?>> {
        val databaseFile = File(storageDirectory, "calendar_core.sqlite3")
        if (!databaseFile.isFile) return emptyList()
        return SQLiteDatabase.openDatabase(
            databaseFile.absolutePath,
            null,
            SQLiteDatabase.OPEN_READONLY,
        ).use { database ->
            database.rawQuery(
                "SELECT payload_json FROM $tableName ORDER BY position",
                null,
            ).use { cursor ->
                buildList {
                    while (cursor.moveToNext()) {
                        add(decode(cursor.getString(0)))
                    }
                }
            }
        }
    }
}
