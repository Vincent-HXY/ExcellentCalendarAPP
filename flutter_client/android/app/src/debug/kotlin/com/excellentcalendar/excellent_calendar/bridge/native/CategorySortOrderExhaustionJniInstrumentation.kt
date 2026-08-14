package com.excellentcalendar.excellent_calendar.bridge.native

import android.app.Activity
import android.app.Application
import android.app.Instrumentation
import android.content.Context
import android.os.Build
import android.os.Bundle
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import java.io.File
import java.security.MessageDigest

/**
 * Exercises the sort-order exhaustion scenario in a fresh instrumentation process.
 *
 * The normal [Application] deliberately replaces the production application for this process, so
 * WorkManager cannot initialize the process-global C++ runtime through the production factory.
 * The runner also uses and removes a dedicated storage directory below app files; production data
 * is never read or mutated.
 */
class CategorySortOrderExhaustionJniInstrumentation : Instrumentation() {
    override fun newApplication(
        classLoader: ClassLoader,
        className: String,
        context: Context,
    ): Application = super.newApplication(classLoader, Application::class.java.name, context)

    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        start()
    }

    override fun onStart() {
        val result = runCatching {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                error("Dedicated-process instrumentation requires Android API 26 or newer")
            }
            val actualProcessName = processName
            check(actualProcessName == DedicatedProcessName) {
                "Category exhaustion JNI smoke is not running in its dedicated process: $actualProcessName"
            }
            CategorySortOrderExhaustionJniRunner.run(targetContext)
        }
        val output = Bundle()
        result.fold(
            onSuccess = { message ->
                output.putString(REPORT_KEY_STREAMRESULT, "$message\n")
                finish(Activity.RESULT_OK, output)
            },
            onFailure = { error ->
                output.putString(REPORT_KEY_STREAMRESULT, "FAIL ${error.stackTraceToString()}\n")
                finish(Activity.RESULT_CANCELED, output)
            },
        )
    }

    private companion object {
        const val DedicatedProcessName =
            "com.excellentcalendar.excellent_calendar:category_sort_order_exhaustion_jni_test"
    }
}

internal object CategorySortOrderExhaustionJniRunner {
    fun run(context: Context): String {
        check(NativeContractRuntimeProfile.current == NativeContractProfile.V2)
        val filesDirectory = context.filesDir.canonicalFile
        val storageDirectory = File(filesDirectory, TestStorageDirectoryName).canonicalFile
        check(storageDirectory.parentFile == filesDirectory) {
            "Category exhaustion smoke storage escaped the app files directory"
        }
        resetTestStorage(storageDirectory)

        val scenarioResult = runCatching {
            val tzdbDirectory = BundledTzdbExtractor.extract(context.applicationContext)
            val bridge = JniNativeCalendarCoreBridge(
                profile = NativeContractProfile.V2,
                runtimeRequestProvider = NativeRuntimeRequestProvider {
                    NativeContractJsonCodec.encodeObject(
                        linkedMapOf(
                            "storage_directory" to storageDirectory.absolutePath,
                            "tzdb_directory" to tzdbDirectory.absolutePath,
                        ),
                    )
                },
            )

            val maximum = decode(
                bridge.createCategory(
                    NativeContractJsonCodec.encodeObject(
                        createRequest(
                            name = "Category maximum sort order",
                            sortOrder = MaximumSafeSortOrder,
                        ),
                    ),
                ),
            )
            verifySuccessEnvelope(maximum, "category.create maximum sort_order")

            val beforeItems = activeItems(bridge.listCategories("{}"), "category.list before exhaustion")
            check(beforeItems.size == 1) { "Expected exactly one Category before exhaustion" }
            check(integer(beforeItems.single()["sort_order"]) == MaximumSafeSortOrder) {
                "Maximum Category sort_order was not persisted exactly"
            }
            val beforeFiles = snapshotFiles(storageDirectory)

            val exhausted = decode(
                bridge.createCategory(
                    NativeContractJsonCodec.encodeObject(
                        createRequest(
                            name = "Category append must fail",
                            sortOrder = null,
                        ),
                    ),
                ),
            )
            verifyFailureEnvelope(
                exhausted,
                "category.create exhausted append",
                NativeErrorCodes.CategorySortOrderExhausted,
                expectedRetryable = false,
            )

            val afterItems = activeItems(bridge.listCategories("{}"), "category.list after exhaustion")
            check(afterItems == beforeItems) {
                "Exhausted Category append changed the observable Category list"
            }
            check(snapshotFiles(storageDirectory) == beforeFiles) {
                "Exhausted Category append wrote to the isolated Store"
            }
            "PASS category max sort_order -> null append returned " +
                "${NativeErrorCodes.CategorySortOrderExhausted}; isolated Store remained byte-stable"
        }

        val cleanupResult = runCatching { removeTestStorage(storageDirectory) }
        scenarioResult.exceptionOrNull()?.let { scenarioError ->
            cleanupResult.exceptionOrNull()?.let(scenarioError::addSuppressed)
            throw scenarioError
        }
        cleanupResult.getOrThrow()
        return scenarioResult.getOrThrow()
    }

    private fun createRequest(name: String, sortOrder: Long?): Map<String, Any?> = linkedMapOf(
        "name" to name,
        "description" to null,
        "color" to "#39AFBD",
        "icon" to null,
        "sort_order" to sortOrder,
    )

    private fun activeItems(json: String, operation: String): List<Map<String, Any?>> {
        val result = decode(json)
        verifySuccessEnvelope(result, operation)
        val data = result["data"] as? Map<*, *> ?: error("$operation returned no data")
        val items = data["items"] as? List<*> ?: error("$operation returned no items")
        return items.mapIndexed { index, item ->
            @Suppress("UNCHECKED_CAST")
            item as? Map<String, Any?> ?: error("$operation item $index is malformed")
        }
    }

    private fun decode(json: String): Map<String, Any?> = NativeContractJsonCodec.decodeObject(json)

    private fun verifySuccessEnvelope(result: Map<String, Any?>, operation: String) {
        verifyExactEnvelope(result, operation)
        check(result["ok"] == true && result["error"] == null) {
            "$operation failed: $result"
        }
    }

    private fun verifyFailureEnvelope(
        result: Map<String, Any?>,
        operation: String,
        expectedCode: String,
        expectedRetryable: Boolean,
    ) {
        verifyExactEnvelope(result, operation)
        check(result["ok"] == false && result["data"] == null) {
            "$operation did not return a failure envelope: $result"
        }
        val error = result["error"] as? Map<*, *> ?: error("$operation returned no NativeError")
        check(error.keys == setOf("code", "message", "details", "retryable")) {
            "$operation returned a non-exact NativeError: ${error.keys}"
        }
        check(error["code"] == expectedCode) { "$operation returned the wrong error: $error" }
        check(error["retryable"] == expectedRetryable) {
            "$operation returned the wrong retryable value: $error"
        }
    }

    private fun verifyExactEnvelope(result: Map<String, Any?>, operation: String) {
        check(result.keys == setOf("ok", "data", "error", "contract_version", "request_id")) {
            "$operation returned a non-exact NativeResult envelope: ${result.keys}"
        }
        check(result["contract_version"] == 2) { "$operation returned the wrong Contract version" }
        check(result["request_id"] is String) { "$operation returned no request_id" }
    }

    private fun integer(value: Any?): Long? = when (value) {
        is Int -> value.toLong()
        is Long -> value
        else -> null
    }

    private fun snapshotFiles(directory: File): Map<String, FileSnapshot> =
        directory.walkTopDown()
            .filter(File::isFile)
            .associate { file ->
                file.relativeTo(directory).invariantSeparatorsPath to FileSnapshot(
                    size = file.length(),
                    modifiedAtMillis = file.lastModified(),
                    sha256 = sha256(file.readBytes()),
                )
            }

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString(separator = "") { byte -> "%02x".format(byte.toInt() and 0xff) }

    private fun resetTestStorage(directory: File) {
        removeTestStorage(directory)
        check(directory.mkdirs()) { "Cannot create isolated Category exhaustion Store" }
    }

    private fun removeTestStorage(directory: File) {
        if (directory.exists()) {
            check(directory.deleteRecursively()) { "Cannot remove isolated Category exhaustion Store" }
        }
    }

    private data class FileSnapshot(
        val size: Long,
        val modifiedAtMillis: Long,
        val sha256: String,
    )

    private const val MaximumSafeSortOrder = 9_007_199_254_740_991L
    private const val TestStorageDirectoryName = "category_sort_order_exhaustion_jni_test"
}
