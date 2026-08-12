package com.excellentcalendar.excellent_calendar.bridge.native

import java.io.File

/**
 * Resolves the Android private directory used by Calendar Core JSON storage.
 *
 * V1 data is not preserved: the historical "test_storage_json" directory is no
 * longer migrated and is not a data source. V2 is the only active writer and
 * uses "calendar_core_storage_json".
 */
internal object CalendarCoreStorageDirectoryResolver {
    private const val LocalStorageDirectoryName = "local_storage"
    private const val CurrentStorageDirectoryName = "calendar_core_storage_json"

    fun resolve(filesDir: File): File =
        File(File(filesDir, LocalStorageDirectoryName), CurrentStorageDirectoryName)
}
