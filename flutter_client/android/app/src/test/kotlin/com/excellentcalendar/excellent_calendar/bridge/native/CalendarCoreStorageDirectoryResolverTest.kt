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

        val resolved = CalendarCoreStorageDirectoryResolver.resolve(filesDir, deviceTest = false)

        assertEquals(currentDirectory(filesDir).canonicalFile, resolved.canonicalFile)
        assertFalse(currentDirectory(filesDir).exists())
    }

    @Test
    fun resolveIgnoresLegacyDirectoryWithoutMigratingIt() {
        val filesDir = temporaryFolder.newFolder("files")
        val legacyDirectory = legacyDirectory(filesDir).also { it.mkdirs() }
        File(legacyDirectory, "events.json").writeText("""{"items":[]}""")

        val resolved = CalendarCoreStorageDirectoryResolver.resolve(filesDir, deviceTest = false)

        assertEquals(currentDirectory(filesDir).canonicalFile, resolved.canonicalFile)
        assertFalse(currentDirectory(filesDir).exists())
        assertTrue(File(legacyDirectory, "events.json").isFile)
    }

    @Test
    fun deviceTestResolutionUsesDedicatedStorageRoot() {
        val filesDir = temporaryFolder.newFolder("device-test-files")

        val resolved = CalendarCoreStorageDirectoryResolver.resolve(filesDir, deviceTest = true)

        assertEquals(
            File(File(filesDir, "local_storage"), "calendar_core_device_test_storage_json").canonicalFile,
            resolved.canonicalFile,
        )
        assertFalse(currentDirectory(filesDir).exists())
    }

    @Test
    fun deviceTestGuardRejectsProductionIdentityOrStorage() {
        val filesDir = temporaryFolder.newFolder("guard-files")
        val isolated = CalendarCoreStorageDirectoryResolver.resolve(filesDir, deviceTest = true)
        val production = CalendarCoreStorageDirectoryResolver.resolve(filesDir, deviceTest = false)

        assertFails {
            CalendarCoreDeviceTestSafetyGuard.verifyConfiguration(
                deviceTestEnabled = true,
                buildApplicationId = "com.excellentcalendar.excellent_calendar",
                runtimePackageName = "com.excellentcalendar.excellent_calendar",
                filesDir = filesDir,
                storageDirectory = isolated,
            )
        }
        assertFails {
            CalendarCoreDeviceTestSafetyGuard.verifyConfiguration(
                deviceTestEnabled = true,
                buildApplicationId = "com.excellentcalendar.excellent_calendar.device_test",
                runtimePackageName = "com.excellentcalendar.excellent_calendar.device_test",
                filesDir = filesDir,
                storageDirectory = production,
            )
        }
    }

    private fun assertFails(block: () -> Unit) {
        try {
            block()
            throw AssertionError("Expected device-test safety guard to reject the configuration.")
        } catch (_: IllegalStateException) {
            // Expected.
        }
    }

    private fun currentDirectory(filesDir: File): File =
        File(File(filesDir, "local_storage"), "calendar_core_storage_json")

    private fun legacyDirectory(filesDir: File): File =
        File(File(filesDir, "local_storage"), "test_storage_json")
}
