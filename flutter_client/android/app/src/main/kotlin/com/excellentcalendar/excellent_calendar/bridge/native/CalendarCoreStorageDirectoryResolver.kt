package com.excellentcalendar.excellent_calendar.bridge.native

import com.excellentcalendar.excellent_calendar.BuildConfig
import java.io.File

/**
 * Resolves the Android private directory used by Calendar Core SQLite storage.
 *
 * The historical "test_storage_json" directory is no longer a data source.
 * SQLite Storage v4 keeps the established directory name so the C++ migration
 * can discover JSON v1/v2/v3 data in place. JSON files retained there become
 * read-only migration snapshots after calendar_core.sqlite3 is committed.
 */
internal object CalendarCoreStorageDirectoryResolver {
    fun resolve(
        filesDir: File,
        deviceTest: Boolean = BuildConfig.CALENDAR_CORE_DEVICE_TEST,
    ): File = CalendarCoreStorageLayout.resolve(filesDir, deviceTest)
}

internal object CalendarCoreStorageLayout {
    private const val LocalStorageDirectoryName = "local_storage"
    private const val ProductionStorageDirectoryName = "calendar_core_storage_json"
    private const val DeviceTestStorageDirectoryName = "calendar_core_device_test_storage_json"

    fun resolve(filesDir: File, deviceTest: Boolean): File = File(
        File(filesDir, LocalStorageDirectoryName),
        if (deviceTest) DeviceTestStorageDirectoryName else ProductionStorageDirectoryName,
    )
}
