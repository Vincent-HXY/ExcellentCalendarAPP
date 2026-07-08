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
    fun resolveMigratesLegacyDirectoryWhenCurrentDirectoryIsMissing() {
        val filesDir = temporaryFolder.newFolder("files")
        val legacyDirectory = legacyDirectory(filesDir).also { it.mkdirs() }
        File(legacyDirectory, "events.json").writeText("""{"items":[]}""")

        val resolved = CalendarCoreStorageDirectoryResolver.resolve(filesDir)

        assertEquals(currentDirectory(filesDir).canonicalFile, resolved.canonicalFile)
        assertTrue(File(currentDirectory(filesDir), "events.json").isFile)
        assertEquals("""{"items":[]}""", File(currentDirectory(filesDir), "events.json").readText())
    }

    @Test
    fun resolveMigratesLegacyDirectoryWhenCurrentDirectoryIsEmpty() {
        val filesDir = temporaryFolder.newFolder("files")
        currentDirectory(filesDir).mkdirs()
        val legacyDirectory = legacyDirectory(filesDir).also { it.mkdirs() }
        File(legacyDirectory, "reminders.json").writeText("""{"items":[]}""")

        val resolved = CalendarCoreStorageDirectoryResolver.resolve(filesDir)

        assertEquals(currentDirectory(filesDir).canonicalFile, resolved.canonicalFile)
        assertTrue(File(currentDirectory(filesDir), "reminders.json").isFile)
        assertEquals("""{"items":[]}""", File(currentDirectory(filesDir), "reminders.json").readText())
    }

    @Test
    fun resolveUsesCurrentDirectoryWhenBothDirectoriesContainData() {
        val filesDir = temporaryFolder.newFolder("files")
        val currentDirectory = currentDirectory(filesDir).also { it.mkdirs() }
        val legacyDirectory = legacyDirectory(filesDir).also { it.mkdirs() }
        File(currentDirectory, "events.json").writeText("current")
        File(legacyDirectory, "events.json").writeText("legacy")

        val resolved = CalendarCoreStorageDirectoryResolver.resolve(filesDir)

        assertEquals(currentDirectory.canonicalFile, resolved.canonicalFile)
        assertEquals("current", File(currentDirectory, "events.json").readText())
        assertEquals("legacy", File(legacyDirectory, "events.json").readText())
    }

    @Test
    fun resolveFallsBackToLegacyDirectoryWhenCurrentPathIsNotDirectory() {
        val filesDir = temporaryFolder.newFolder("files")
        val currentPath = currentDirectory(filesDir).also {
            it.parentFile?.mkdirs()
            it.writeText("not a directory")
        }
        val legacyDirectory = legacyDirectory(filesDir).also { it.mkdirs() }
        File(legacyDirectory, "events.json").writeText("legacy")

        val resolved = CalendarCoreStorageDirectoryResolver.resolve(filesDir)

        assertEquals(legacyDirectory.canonicalFile, resolved.canonicalFile)
        assertTrue(currentPath.isFile)
        assertEquals("legacy", File(legacyDirectory, "events.json").readText())
    }

    private fun currentDirectory(filesDir: File): File =
        File(File(filesDir, "local_storage"), "calendar_core_storage_json")

    private fun legacyDirectory(filesDir: File): File =
        File(File(filesDir, "local_storage"), "test_storage_json")
}
