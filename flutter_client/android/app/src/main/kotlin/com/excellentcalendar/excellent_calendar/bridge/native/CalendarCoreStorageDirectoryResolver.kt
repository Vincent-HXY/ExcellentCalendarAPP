package com.excellentcalendar.excellent_calendar.bridge.native

import android.util.Log
import java.io.File
import kotlin.io.OnErrorAction

/**
 * Resolves the Android private directory used by Calendar Core JSON storage.
 *
 * The previous runtime directory was named "test_storage_json" even though it was used by
 * production app data. Keep it as a legacy migration source, but initialize new bridges with
 * "calendar_core_storage_json".
 */
internal object CalendarCoreStorageDirectoryResolver {
    private const val LogTag = "CalendarCoreStorage"
    private const val LocalStorageDirectoryName = "local_storage"
    private const val CurrentStorageDirectoryName = "calendar_core_storage_json"
    private const val LegacyStorageDirectoryName = "test_storage_json"

    fun resolve(filesDir: File): File {
        val localStorageRoot = File(filesDir, LocalStorageDirectoryName)
        val currentDirectory = File(localStorageRoot, CurrentStorageDirectoryName)
        val legacyDirectory = File(localStorageRoot, LegacyStorageDirectoryName)

        val migrationResult = migrateLegacyDirectory(
            legacyDirectory = legacyDirectory,
            currentDirectory = currentDirectory,
        )

        return selectDirectory(
            currentDirectory = currentDirectory,
            legacyDirectory = legacyDirectory,
            migrationResult = migrationResult,
        )
    }

    private fun migrateLegacyDirectory(
        legacyDirectory: File,
        currentDirectory: File,
    ): LegacyMigrationResult {
        if (!legacyDirectory.exists()) {
            return LegacyMigrationResult.NotNeeded
        }
        if (!legacyDirectory.isDirectory) {
            Log.w(LogTag, "Legacy Calendar Core storage path is not a directory: ${legacyDirectory.absolutePath}")
            return LegacyMigrationResult.NotNeeded
        }

        if (currentDirectory.exists()) {
            if (!currentDirectory.isDirectory) {
                Log.w(LogTag, "Current Calendar Core storage path is not a directory: ${currentDirectory.absolutePath}")
                return LegacyMigrationResult.Failed
            }
            if (!currentDirectory.isEmptyDirectory()) {
                Log.w(
                    LogTag,
                    "Both legacy and current Calendar Core storage directories contain data; using current directory",
                )
                return LegacyMigrationResult.SkippedBecauseCurrentHasData
            }
            if (!currentDirectory.deleteRecursively()) {
                Log.w(
                    LogTag,
                    "Failed to remove empty current Calendar Core storage directory before legacy migration",
                )
                return LegacyMigrationResult.Failed
            }
        }

        currentDirectory.parentFile?.mkdirs()
        if (legacyDirectory.renameTo(currentDirectory)) {
            Log.i(
                LogTag,
                "Migrated Calendar Core storage directory from legacy name to ${currentDirectory.absolutePath}",
            )
            return LegacyMigrationResult.Migrated
        }

        Log.w(LogTag, "Failed to rename legacy Calendar Core storage directory; falling back to recursive copy")
        return if (copyLegacyDirectory(legacyDirectory = legacyDirectory, currentDirectory = currentDirectory)) {
            Log.i(
                LogTag,
                "Copied legacy Calendar Core storage directory to ${currentDirectory.absolutePath}",
            )
            LegacyMigrationResult.Migrated
        } else {
            LegacyMigrationResult.Failed
        }
    }

    private fun copyLegacyDirectory(
        legacyDirectory: File,
        currentDirectory: File,
    ): Boolean {
        val copied = legacyDirectory.copyRecursively(
            target = currentDirectory,
            overwrite = false,
        ) { file, exception ->
            Log.w(LogTag, "Failed to copy Calendar Core storage file: ${file.absolutePath}", exception)
            OnErrorAction.TERMINATE
        }

        if (!copied) {
            currentDirectory.deleteRecursively()
            Log.w(LogTag, "Failed to copy legacy Calendar Core storage directory; keeping legacy directory active")
        }
        return copied
    }

    private fun selectDirectory(
        currentDirectory: File,
        legacyDirectory: File,
        migrationResult: LegacyMigrationResult,
    ): File {
        if (migrationResult == LegacyMigrationResult.Failed && legacyDirectory.isDirectory) {
            Log.w(
                LogTag,
                "Using legacy Calendar Core storage directory because migration did not complete",
            )
            return legacyDirectory
        }

        if (currentDirectory.exists()) {
            if (currentDirectory.isDirectory) {
                return currentDirectory
            }
            if (legacyDirectory.isDirectory) {
                Log.w(
                    LogTag,
                    "Using legacy Calendar Core storage directory because current path is not a directory",
                )
                return legacyDirectory
            }
            return currentDirectory
        }

        if (legacyDirectory.isDirectory) {
            Log.w(
                LogTag,
                "Using legacy Calendar Core storage directory because migration did not create current directory",
            )
            return legacyDirectory
        }

        return currentDirectory
    }

    private fun File.isEmptyDirectory(): Boolean = isDirectory && list()?.isEmpty() == true

    private enum class LegacyMigrationResult {
        NotNeeded,
        Migrated,
        SkippedBecauseCurrentHasData,
        Failed,
    }
}
