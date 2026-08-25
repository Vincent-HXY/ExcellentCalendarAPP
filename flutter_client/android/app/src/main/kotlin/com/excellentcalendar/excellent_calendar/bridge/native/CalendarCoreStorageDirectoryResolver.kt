package com.excellentcalendar.excellent_calendar.bridge.native

import com.excellentcalendar.excellent_calendar.BuildConfig
import java.io.File

/**
 * Resolves the Android private directory used by Calendar Core JSON storage.
 *
 * The historical "test_storage_json" directory is no longer a data source.
 * Storage v3 migrates the formal v2 directory in place and remains the only
 * writer of "calendar_core_storage_json".
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
