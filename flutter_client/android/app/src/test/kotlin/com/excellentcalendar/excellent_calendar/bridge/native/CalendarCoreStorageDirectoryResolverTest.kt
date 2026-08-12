package com.excellentcalendar.excellent_calendar.bridge.native

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class CalendarCoreStorageDirectoryResolverTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun resolveReturnsCurrentDirectoryWhenNoStorageExists() {
        val filesDir = temporaryFolder.newFolder("files")

        val resolved = CalendarCoreStorageDirectoryResolver.resolve(filesDir)

        assertEquals(currentDirectory(filesDir).canonicalFile, resolved.canonicalFile)
        assertFalse(currentDirectory(filesDir).exists())
    }

    @Test
    fun resolveIgnoresLegacyDirectoryWithoutMigratingIt() {
        val filesDir = temporaryFolder.newFolder("files")
        val legacyDirectory = legacyDirectory(filesDir).also { it.mkdirs() }
        File(legacyDirectory, "events.json").writeText("""{"items":[]}""")

        val resolved = CalendarCoreStorageDirectoryResolver.resolve(filesDir)

        assertEquals(currentDirectory(filesDir).canonicalFile, resolved.canonicalFile)
        assertFalse(currentDirectory(filesDir).exists())
        assertTrue(File(legacyDirectory, "events.json").isFile)
    }

    private fun currentDirectory(filesDir: File): File =
        File(File(filesDir, "local_storage"), "calendar_core_storage_json")

    private fun legacyDirectory(filesDir: File): File =
        File(File(filesDir, "local_storage"), "test_storage_json")
}
