package com.excellentcalendar.excellent_calendar.android.search

import android.content.Context
import android.content.pm.ApplicationInfo
import android.util.AtomicFile
import com.excellentcalendar.excellent_calendar.BuildConfig
import com.excellentcalendar.excellent_calendar.bridge.native.CalendarCoreDeviceTestSafetyGuard
import java.io.File

/** Two-step ADB crash-recovery proof for the real no-backup AtomicFile. */
internal object SearchHistoryDeviceSmokeRunner {
    fun prepareInterruptedWrite(context: Context): String {
        val appContext = verifiedContext(context)
        val store = SearchHistoryStoreProvider.get(appContext)
        val current = store.get().success()
        val prepared = store.replace(current.revision, listOf(Marker)).success()
        val baseFile = File(appContext.noBackupFilesDir, AtomicFileSearchHistoryStore.FileName).canonicalFile
        check(baseFile.parentFile == appContext.noBackupFilesDir.canonicalFile)
        val interrupted = AtomicFile(baseFile).startWrite()
        interrupted.write("{\"schema_version\":1,\"revision\":".toByteArray(Charsets.UTF_8))
        interrupted.flush()
        interrupted.close()
        return "PASS prepare Search history interrupted write at revision=${prepared.revision}; force-stop then run verify"
    }

    fun verifyRestartRecovery(context: Context): String {
        val appContext = verifiedContext(context)
        val baseFile = File(appContext.noBackupFilesDir, AtomicFileSearchHistoryStore.FileName).canonicalFile
        check(baseFile.parentFile == appContext.noBackupFilesDir.canonicalFile)
        val store = SearchHistoryStoreProvider.get(appContext)
        val recovered = store.get().success()
        check(recovered.items == listOf(Marker)) { "AtomicFile did not recover the previous complete snapshot" }
        val cleared = store.replace(recovered.revision, emptyList()).success()
        check(cleared.items.isEmpty())
        return "PASS restart Search history: recovered old complete AtomicFile snapshot, noBackup owner, cleanup revision=${cleared.revision}"
    }

    private fun verifiedContext(context: Context): Context {
        val appContext = context.applicationContext
        check(BuildConfig.CALENDAR_CORE_DEVICE_TEST)
        check(BuildConfig.APPLICATION_ID.endsWith(DeviceTestApplicationIdSuffix))
        check(appContext.packageName == BuildConfig.APPLICATION_ID)
        CalendarCoreDeviceTestSafetyGuard.verify(appContext)
        check(appContext.noBackupFilesDir.canonicalFile != appContext.filesDir.canonicalFile)
        check(appContext.applicationInfo.flags and ApplicationInfo.FLAG_ALLOW_BACKUP != 0) {
            "Search must not globally disable the existing application backup policy"
        }
        return appContext
    }

    private fun SearchHistoryStoreResult.success(): SearchHistorySnapshot =
        (this as? SearchHistoryStoreResult.Success)?.snapshot ?: error("Search history operation failed: $this")

    private const val DeviceTestApplicationIdSuffix = ".device_test"
    private const val Marker = "Search restart 原子历史😀"
}
