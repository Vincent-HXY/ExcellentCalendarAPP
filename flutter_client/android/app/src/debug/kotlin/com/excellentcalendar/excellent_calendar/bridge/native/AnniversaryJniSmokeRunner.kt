package com.excellentcalendar.excellent_calendar.bridge.native

import android.content.Context
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import java.io.File

internal object AnniversaryJniSmokeRunner {
    fun run(context: Context): String {
        val storageDirectory = CalendarCoreV2StorageDirectoryResolver.resolve(
            context.filesDir,
        )
        val bridge = AndroidNativeBridgeFactory.create(context)
        val create = NativeContractJsonCodec.decodeObject(
            bridge.createAnniversary(
                NativeContractJsonCodec.encodeObject(
                    linkedMapOf(
                        "title" to "JNI smoke anniversary",
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
        check(
            File(storageDirectory, "anniversaries.json").isFile &&
                File(storageDirectory, "anniversary_recurrences.json").isFile &&
                File(storageDirectory, "anniversary_workflow_transactions.json").isFile,
        ) {
            "Anniversary v2 storage files were not materialized"
        }

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
        return "PASS create->detail persisted id=$anniversaryId; soft-delete cleanup passed"
    }
}
