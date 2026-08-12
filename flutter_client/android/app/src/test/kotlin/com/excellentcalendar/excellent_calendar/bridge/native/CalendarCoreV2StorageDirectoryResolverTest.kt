package com.excellentcalendar.excellent_calendar.bridge.native

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

class CalendarCoreV2StorageDirectoryResolverTest {
    @Test
    fun v2StorageResolverDoesNotTouchFormalOrLegacyDirectories() {
        val filesDir = Files.createTempDirectory("calendar-v2-storage").toFile()
        try {
            val active = filesDir.resolve("local_storage/calendar_core_storage_json")
            val legacy = filesDir.resolve("local_storage/test_storage_json")
            assertTrue(active.mkdirs())
            assertTrue(legacy.mkdirs())
            active.resolve("events.json").writeText("formal-v1")
            legacy.resolve("events.json").writeText("[]")

            val resolved = CalendarCoreV2StorageDirectoryResolver.resolve(filesDir)

            assertEquals(active, resolved)
            assertEquals("formal-v1", active.resolve("events.json").readText())
            assertTrue(legacy.resolve("events.json").isFile)
            assertTrue(filesDir.resolve("local_storage/calendar_core_storage_v2").notExists())
        } finally {
            filesDir.deleteRecursively()
        }
    }

    @Test
    fun v2StorageReturnsTheContractPathWithoutCreatingOrMovingAnything() {
        val filesDir = Files.createTempDirectory("calendar-v2-storage").toFile()
        try {
            val root = filesDir.resolve("local_storage")
            val legacy = root.resolve("test_storage_json")
            assertTrue(legacy.mkdirs())
            legacy.resolve("events.json").writeText("v1")

            val active = root.resolve("calendar_core_storage_json")
            assertEquals(active, CalendarCoreV2StorageDirectoryResolver.resolve(filesDir))
            assertTrue(active.notExists())
            assertTrue(legacy.resolve("events.json").isFile)
        } finally {
            filesDir.deleteRecursively()
        }
    }

    private fun java.io.File.notExists(): Boolean = !exists()
}
