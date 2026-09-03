package com.excellentcalendar.excellent_calendar.android.search

import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.SearchContracts
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileNotFoundException
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class SearchHistoryStoreTest {
    @Test
    fun missingReadReplaceIdempotenceConflictAndClearAreMonotonic() {
        val file = FakeAtomicFile()
        val store = store(file)

        assertEquals(SearchHistorySnapshot(0, emptyList()), store.get().success())
        assertEquals(SearchHistorySnapshot(1, listOf("项目", "Meeting")), store.replace(0, listOf("项目", "Meeting")).success())
        assertEquals(1, file.finishCount)
        assertEquals(SearchHistorySnapshot(1, listOf("项目", "Meeting")), store.replace(1, listOf("项目", "Meeting")).success())
        assertEquals(1, file.finishCount)
        assertEquals(NativeErrorCodes.SearchHistoryConflict, store.replace(0, emptyList()).failure().code)
        assertEquals(1, file.finishCount)
        assertEquals(SearchHistorySnapshot(2, emptyList()), store.replace(1, emptyList()).success())
    }

    @Test
    fun knownV1CorruptionRepairsAtomicallyWithOneRevisionAndNoContentLogs() {
        val raw = """{"schema_version":1,"revision":4,"keywords":["  项目　MEETING  ","meeting","MEETING","年度回顾","年度回顾"],"extra":true}"""
        val logs = mutableListOf<String>()
        val file = FakeAtomicFile(raw.toByteArray())
        val store = store(file, logs)

        assertEquals(
            SearchHistorySnapshot(5, listOf("项目 MEETING", "meeting", "年度回顾")),
            store.get().success(),
        )
        assertEquals(1, file.finishCount)
        assertTrue(logs.none { it.contains("项目") || it.contains("MEETING") || it.contains(raw) })
    }

    @Test
    fun futureVersionAndRevisionExhaustionPreserveExactBytes() {
        val future = """{"schema_version":2,"revision":9,"keywords":["future"]}""".toByteArray()
        val futureFile = FakeAtomicFile(future.copyOf())
        assertEquals(NativeErrorCodes.SearchHistoryStorageFailed, store(futureFile).get().failure().code)
        assertArrayEquals(future, futureFile.bytes)
        assertEquals(0, futureFile.finishCount)

        val maximum = SearchHistoryCodec.encode(SearchHistorySnapshot(SearchContracts.MaximumSafeInteger, listOf("项目")))
        val maximumFile = FakeAtomicFile(maximum.copyOf())
        val maximumStore = store(maximumFile)
        assertEquals(
            SearchHistorySnapshot(SearchContracts.MaximumSafeInteger, listOf("项目")),
            maximumStore.replace(SearchContracts.MaximumSafeInteger, listOf("项目")).success(),
        )
        assertEquals(
            NativeErrorCodes.SearchHistoryStorageFailed,
            maximumStore.replace(SearchContracts.MaximumSafeInteger, listOf("会议")).failure().code,
        )
        assertArrayEquals(maximum, maximumFile.bytes)
        assertEquals(0, maximumFile.finishCount)
    }

    @Test
    fun startWriteWriteAndFinishWriteFailuresKeepOldBytesAndCommittedSnapshot() {
        FailurePhase.values().filter { it != FailurePhase.NONE }.forEach { phase ->
            val old = SearchHistoryCodec.encode(SearchHistorySnapshot(3, listOf("旧值")))
            val file = FakeAtomicFile(old.copyOf(), failure = phase)
            val store = store(file)
            assertEquals(SearchHistorySnapshot(3, listOf("旧值")), store.get().success())

            val failure = store.replace(3, listOf("新值")).failure()
            assertEquals("phase=$phase", NativeErrorCodes.SearchHistoryStorageFailed, failure.code)
            assertArrayEquals("phase=$phase", old, file.bytes)
            assertEquals(SearchHistorySnapshot(3, listOf("旧值")), store.committedSnapshotForTest())
            assertEquals(1, file.failCount)
        }
    }

    @Test
    fun concurrentCompareAndReplaceAllowsExactlyOneWinner() {
        val file = FakeAtomicFile(SearchHistoryCodec.encode(SearchHistorySnapshot(0, emptyList())))
        val store = store(file)
        val start = CountDownLatch(1)
        val pool = Executors.newFixedThreadPool(2)
        try {
            val futures = listOf("A", "B").map { item ->
                pool.submit<SearchHistoryStoreResult> {
                    start.await(5, TimeUnit.SECONDS)
                    store.replace(0, listOf(item))
                }
            }
            start.countDown()
            val results = futures.map { it.get(5, TimeUnit.SECONDS) }
            assertEquals(1, results.count { it is SearchHistoryStoreResult.Success })
            assertEquals(1, results.count { it is SearchHistoryStoreResult.Failure && it.code == NativeErrorCodes.SearchHistoryConflict })
            assertEquals(1, file.finishCount)
        } finally {
            pool.shutdownNow()
        }
    }

    @Test
    fun canonicalPathCannotDriftOutsideNoBackupDirectory() {
        val root = File(System.getProperty("java.io.tmpdir"), "search-history-path-test")
        val noBackup = File(root, "no_backup")
        val wrong = File(root, AtomicFileSearchHistoryStore.FileName)
        assertThrows(IllegalArgumentException::class.java) {
            AtomicFileSearchHistoryStore(wrong, noBackup, FakeAtomicFile())
        }
    }

    private fun store(file: FakeAtomicFile, logs: MutableList<String> = mutableListOf()): AtomicFileSearchHistoryStore {
        val noBackup = File(System.getProperty("java.io.tmpdir"), "excellent-calendar-search-test").canonicalFile
        return AtomicFileSearchHistoryStore(
            File(noBackup, AtomicFileSearchHistoryStore.FileName),
            noBackup,
            file,
            SearchHistoryStoreLogger(logs::add),
        )
    }

    private fun SearchHistoryStoreResult.success(): SearchHistorySnapshot =
        (this as SearchHistoryStoreResult.Success).snapshot

    private fun SearchHistoryStoreResult.failure(): SearchHistoryStoreResult.Failure =
        this as SearchHistoryStoreResult.Failure

    private enum class FailurePhase { NONE, START, WRITE, FINISH }

    private class FakeAtomicFile(
        var bytes: ByteArray? = null,
        private var failure: FailurePhase = FailurePhase.NONE,
    ) : SearchHistoryAtomicFile {
        var finishCount = 0
        var failCount = 0
        private var pending: ByteArrayOutputStream? = null

        override fun openRead(): InputStream = bytes?.let(::ByteArrayInputStream) ?: throw FileNotFoundException()

        override fun startWrite(): OutputStream {
            if (failure == FailurePhase.START) throw IllegalStateException("start failure")
            val target = ByteArrayOutputStream()
            pending = target
            return if (failure == FailurePhase.WRITE) {
                object : OutputStream() {
                    override fun write(value: Int) = throw IllegalStateException("write failure")
                    override fun write(value: ByteArray, offset: Int, length: Int) = throw IllegalStateException("write failure")
                }
            } else {
                target
            }
        }

        override fun finishWrite(stream: OutputStream) {
            if (failure == FailurePhase.FINISH) throw IllegalStateException("finish failure")
            bytes = (stream as ByteArrayOutputStream).toByteArray()
            pending = null
            finishCount += 1
        }

        override fun failWrite(stream: OutputStream?) {
            failCount += 1
            pending = null
        }
    }
}
