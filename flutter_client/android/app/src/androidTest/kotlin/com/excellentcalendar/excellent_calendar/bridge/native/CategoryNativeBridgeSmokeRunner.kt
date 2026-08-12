package com.excellentcalendar.excellent_calendar.bridge.native

import android.content.Context
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import java.io.File

/** Device smoke for Category JNI, JSON v2 persistence, and runtime reinitialization. */
internal object CategoryNativeBridgeSmokeRunner {
    fun run(context: Context): String {
        check(NativeContractRuntimeProfile.current == NativeContractProfile.V2)
        val storageDirectory = CalendarCoreV2StorageDirectoryResolver.resolve(context.filesDir)
        val bridge = AndroidNativeBridgeFactory.create(context)
        verifyFailureEnvelope(
            NativeContractJsonCodec.decodeObject(bridge.createCategory("[")),
            "category.create malformed JSON",
            NativeErrorCodes.ContractValidationFailed,
        )
        val malformedUtf16 =
            "{\"name\":\"" + '\uD800' +
                "\",\"description\":null,\"color\":\"#39AFBD\",\"icon\":null,\"sort_order\":null}"
        verifyFailureEnvelope(
            NativeContractJsonCodec.decodeObject(bridge.createCategory(malformedUtf16)),
            "category.create malformed UTF-16",
            NativeErrorCodes.ContractValidationFailed,
        )
        val before = activeItems(bridge.listCategories("{}"), "category.list before create")
        val existing = before.firstOrNull { it["name"] == MarkerName }
        val category = existing ?: createMarker(bridge)
        val categoryId = category["id"] as? String
            ?: error("category.create/list returned no id")

        check(File(storageDirectory, "categories.json").isFile) {
            "Category v2 storage file was not materialized"
        }

        val reinitialized = NativeContractJsonCodec.decodeObject(
            bridge.initializeRuntime(
                CalendarCoreV2RuntimeRequestProvider(context.applicationContext).createRequestJson(),
            ),
        )
        verifySuccessEnvelope(reinitialized, "runtime reinitialize")

        val after = activeItems(bridge.listCategories("{}"), "category.list after restart")
        val reloaded = after.firstOrNull { it["id"] == categoryId }
            ?: error("Category id $categoryId was not recovered after runtime restart")
        check(reloaded["name"] == MarkerName) { "Unicode Category name changed after restart" }
        check(reloaded["description"] == MarkerDescription) {
            "Unicode Category description changed after restart"
        }
        check(reloaded["icon"] == MarkerIcon) { "Unicode Category icon changed after restart" }
        check(reloaded["color"] == "#39AFBD") { "Category color was not canonicalized" }
        check(reloaded["sort_order"] is Int || reloaded["sort_order"] is Long) {
            "Category default sort_order was not materialized"
        }
        return "PASS category create/list JNI persisted id=$categoryId; runtime restart recovered it" +
            if (existing != null) "; prior app-process data was also recovered" else ""
    }

    private fun createMarker(bridge: NativeCalendarCoreBridge): Map<String, Any?> {
        val result = NativeContractJsonCodec.decodeObject(
            bridge.createCategory(
                NativeContractJsonCodec.encodeObject(
                    linkedMapOf(
                        "name" to MarkerName,
                        "description" to "  $MarkerDescription  ",
                        "color" to "#39afbd",
                        "icon" to "  $MarkerIcon  ",
                        "sort_order" to null,
                    ),
                ),
            ),
        )
        verifySuccessEnvelope(result, "category.create")
        @Suppress("UNCHECKED_CAST")
        return result["data"] as? Map<String, Any?>
            ?: error("category.create returned no CategoryResponse")
    }

    private fun activeItems(json: String, operation: String): List<Map<String, Any?>> {
        val result = NativeContractJsonCodec.decodeObject(json)
        verifySuccessEnvelope(result, operation)
        val data = result["data"] as? Map<*, *> ?: error("$operation returned no data")
        val items = data["items"] as? List<*> ?: error("$operation returned no items")
        return items.mapIndexed { index, item ->
            @Suppress("UNCHECKED_CAST")
            item as? Map<String, Any?> ?: error("$operation item $index is malformed")
        }
    }

    private fun verifySuccessEnvelope(result: Map<String, Any?>, operation: String) {
        check(result.keys == setOf("ok", "data", "error", "contract_version", "request_id")) {
            "$operation returned a non-exact NativeResult envelope: ${result.keys}"
        }
        check(result["ok"] == true && result["error"] == null) {
            "$operation failed: $result"
        }
        check(result["contract_version"] == 2) { "$operation returned the wrong Contract version" }
        check(result["request_id"] is String) { "$operation returned no request_id" }
    }

    private fun verifyFailureEnvelope(
        result: Map<String, Any?>,
        operation: String,
        expectedCode: String,
    ) {
        check(result.keys == setOf("ok", "data", "error", "contract_version", "request_id")) {
            "$operation returned a non-exact NativeResult envelope: ${result.keys}"
        }
        check(result["ok"] == false && result["data"] == null) {
            "$operation did not return a failure envelope: $result"
        }
        val error = result["error"] as? Map<*, *> ?: error("$operation returned no NativeError")
        check(error["code"] == expectedCode) { "$operation returned the wrong error: $error" }
        check(result["contract_version"] == 2) { "$operation returned the wrong Contract version" }
        check(result["request_id"] is String) { "$operation returned no request_id" }
    }

    private const val MarkerName = "JNI 分类重启🗓️"
    private const val MarkerDescription = "中文与 emoji 持久化🚀"
    private const val MarkerIcon = "folder_📁"
}
