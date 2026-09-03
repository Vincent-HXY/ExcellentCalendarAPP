package com.excellentcalendar.excellent_calendar.android.search

import android.content.Context
import android.util.AtomicFile
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeContractViolation
import com.excellentcalendar.excellent_calendar.bridge.contract.SearchContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.SearchTextContract
import java.io.File
import java.io.FileInputStream
import java.io.FileNotFoundException
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream

sealed interface SearchHistoryStoreResult {
    data class Success(val snapshot: SearchHistorySnapshot) : SearchHistoryStoreResult
    data class Failure(
        val code: String,
        val message: String,
        val reason: String,
        val retryable: Boolean,
    ) : SearchHistoryStoreResult
}

interface SearchHistoryStore {
    fun get(): SearchHistoryStoreResult

    fun replace(expectedRevision: Long, items: List<String>): SearchHistoryStoreResult
}

fun interface SearchHistoryStoreLogger {
    fun log(category: String)
}

internal interface SearchHistoryAtomicFile {
    fun openRead(): InputStream
    fun startWrite(): OutputStream
    fun finishWrite(stream: OutputStream)
    fun failWrite(stream: OutputStream?)
}

private class AndroidSearchHistoryAtomicFile(file: File) : SearchHistoryAtomicFile {
    private val atomicFile = AtomicFile(file)

    override fun openRead(): FileInputStream = atomicFile.openRead()

    override fun startWrite(): FileOutputStream = atomicFile.startWrite()

    override fun finishWrite(stream: OutputStream) {
        atomicFile.finishWrite(stream as FileOutputStream)
    }

    override fun failWrite(stream: OutputStream?) {
        atomicFile.failWrite(stream as FileOutputStream?)
    }
}

/**
 * Process-singleton, lock-owned AtomicFile store. Disk bytes remain authoritative; the committed
 * snapshot is published only after a valid read or a confirmed finishWrite.
 */
class AtomicFileSearchHistoryStore internal constructor(
    baseFile: File,
    expectedNoBackupDirectory: File,
    private val atomicFile: SearchHistoryAtomicFile = AndroidSearchHistoryAtomicFile(baseFile),
    private val logger: SearchHistoryStoreLogger = SearchHistoryStoreLogger { },
) : SearchHistoryStore {
    private val lock = Any()
    private val canonicalBaseFile = baseFile.canonicalFile
    private val canonicalNoBackupDirectory = expectedNoBackupDirectory.canonicalFile

    @Volatile
    private var committedSnapshot: SearchHistorySnapshot? = null

    init {
        require(canonicalBaseFile.parentFile == canonicalNoBackupDirectory) {
            "Search history must be stored directly in noBackupFilesDir."
        }
        require(canonicalBaseFile.name == FileName) { "Search history file name is fixed by Contract." }
    }

    override fun get(): SearchHistoryStoreResult = synchronized(lock) {
        when (val loaded = readLocked()) {
            is Loaded.Missing -> success(InitialSnapshot)
            is Loaded.Valid -> {
                if (!loaded.needsRepair) {
                    success(loaded.snapshot)
                } else if (loaded.snapshot.revision == SearchContracts.MaximumSafeInteger) {
                    storageFailure("repair_revision_exhausted")
                } else {
                    val repaired = loaded.snapshot.copy(revision = loaded.snapshot.revision + 1)
                    if (commitLocked(repaired, loaded.corruptionCategory ?: "known_v1_corruption")) {
                        success(repaired)
                    } else {
                        storageFailure("repair_commit_failed")
                    }
                }
            }
            is Loaded.Failure -> storageFailure(loaded.reason)
        }
    }

    override fun replace(expectedRevision: Long, items: List<String>): SearchHistoryStoreResult {
        try {
            if (expectedRevision !in 0..SearchContracts.MaximumSafeInteger) {
                throw NativeContractViolation("expected_revision is out of range.", "expected_revision")
            }
            SearchTextContract.requireCanonicalHistory(items, "items")
        } catch (_: NativeContractViolation) {
            return storageFailure("invalid_store_input")
        }
        return synchronized(lock) {
            when (val loaded = readLocked()) {
                is Loaded.Failure -> storageFailure(loaded.reason)
                is Loaded.Missing -> replaceLoaded(InitialSnapshot, needsRepair = false, expectedRevision, items)
                is Loaded.Valid -> replaceLoaded(loaded.snapshot, loaded.needsRepair, expectedRevision, items)
            }
        }
    }

    internal fun committedSnapshotForTest(): SearchHistorySnapshot? = committedSnapshot

    private fun replaceLoaded(
        current: SearchHistorySnapshot,
        needsRepair: Boolean,
        expectedRevision: Long,
        items: List<String>,
    ): SearchHistoryStoreResult {
        if (expectedRevision != current.revision) {
            return SearchHistoryStoreResult.Failure(
                code = NativeErrorCodes.SearchHistoryConflict,
                message = "Device-local search history changed after the supplied revision.",
                reason = "revision_mismatch",
                retryable = true,
            )
        }
        if (!needsRepair && current.items == items) return success(current)
        if (current.revision == SearchContracts.MaximumSafeInteger) {
            return storageFailure("replace_revision_exhausted")
        }
        val replacement = SearchHistorySnapshot(current.revision + 1, items.toList())
        return if (commitLocked(replacement, if (needsRepair) "replace_known_v1_corruption" else "replace")) {
            success(replacement)
        } else {
            storageFailure("replace_commit_failed")
        }
    }

    private fun readLocked(): Loaded {
        val bytes = try {
            atomicFile.openRead().use { stream ->
                val output = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(4096)
                var total = 0
                while (true) {
                    val count = stream.read(buffer)
                    if (count < 0) break
                    total += count
                    if (total > MaximumReadBytes) return Loaded.Failure("file_too_large")
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            }
        } catch (_: FileNotFoundException) {
            return Loaded.Missing
        } catch (_: Throwable) {
            logger.log("read_failed")
            return Loaded.Failure("read_failed")
        }
        return when (val decoded = SearchHistoryCodec.decode(bytes)) {
            is SearchHistoryDecodeResult.KnownV1 -> Loaded.Valid(
                decoded.snapshot,
                decoded.needsRepair,
                decoded.corruptionCategory,
            )
            is SearchHistoryDecodeResult.UnsupportedVersion -> {
                logger.log("future_version")
                Loaded.Failure("future_version")
            }
            is SearchHistoryDecodeResult.Unreadable -> {
                logger.log(decoded.category)
                Loaded.Failure(decoded.category)
            }
        }
    }

    private fun commitLocked(snapshot: SearchHistorySnapshot, category: String): Boolean {
        var stream: OutputStream? = null
        return try {
            stream = atomicFile.startWrite()
            val bytes = SearchHistoryCodec.encode(snapshot)
            stream.write(bytes)
            stream.flush()
            atomicFile.finishWrite(stream)
            committedSnapshot = snapshot
            true
        } catch (_: Throwable) {
            try {
                atomicFile.failWrite(stream)
            } catch (_: Throwable) {
                logger.log("fail_write_failed")
            }
            logger.log("${category}_commit_failed")
            false
        }
    }

    private fun success(snapshot: SearchHistorySnapshot): SearchHistoryStoreResult.Success {
        committedSnapshot = snapshot
        return SearchHistoryStoreResult.Success(snapshot)
    }

    private fun storageFailure(reason: String): SearchHistoryStoreResult.Failure =
        SearchHistoryStoreResult.Failure(
            code = NativeErrorCodes.SearchHistoryStorageFailed,
            message = "Device-local search history could not be read or atomically committed.",
            reason = reason,
            retryable = true,
        )

    private sealed interface Loaded {
        data object Missing : Loaded
        data class Valid(
            val snapshot: SearchHistorySnapshot,
            val needsRepair: Boolean,
            val corruptionCategory: String?,
        ) : Loaded
        data class Failure(val reason: String) : Loaded
    }

    companion object {
        const val FileName = "excellent_calendar_search_history_v1.json"
        private const val MaximumReadBytes = 65_536
        private val InitialSnapshot = SearchHistorySnapshot(0, emptyList())
    }
}

/** Application-context production composition and the only process owner of the history lock. */
object SearchHistoryStoreProvider {
    @Volatile
    private var instance: SearchHistoryStore? = null

    fun get(context: Context): SearchHistoryStore {
        val applicationContext = context.applicationContext
        return instance ?: synchronized(this) {
            instance ?: create(applicationContext).also { instance = it }
        }
    }

    private fun create(context: Context): SearchHistoryStore {
        val noBackupDirectory = context.noBackupFilesDir.canonicalFile
        val file = File(noBackupDirectory, AtomicFileSearchHistoryStore.FileName).canonicalFile
        require(file.parentFile == noBackupDirectory) { "Search history path escaped noBackupFilesDir." }
        return AtomicFileSearchHistoryStore(
            baseFile = file,
            expectedNoBackupDirectory = noBackupDirectory,
            logger = SearchHistoryStoreLogger { category ->
                android.util.Log.w(LogTag, "category=$category")
            },
        )
    }

    private const val LogTag = "SearchHistoryStore"
}
