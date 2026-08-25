package com.excellentcalendar.excellent_calendar.bridge.native

import android.content.Context
import com.excellentcalendar.excellent_calendar.BuildConfig
import java.io.File

/** Fails before native/runtime side effects when a device-test build loses sandbox isolation. */
internal object CalendarCoreDeviceTestSafetyGuard {
    private const val ProductionApplicationId = "com.excellentcalendar.excellent_calendar"
    private const val DeviceTestApplicationId = "$ProductionApplicationId.device_test"

    fun verify(context: Context) {
        val applicationContext = context.applicationContext
        verifyConfiguration(
            deviceTestEnabled = BuildConfig.CALENDAR_CORE_DEVICE_TEST,
            buildApplicationId = BuildConfig.APPLICATION_ID,
            runtimePackageName = applicationContext.packageName,
            filesDir = applicationContext.filesDir,
            storageDirectory = CalendarCoreV2StorageDirectoryResolver.resolve(applicationContext.filesDir),
        )
    }

    internal fun verifyConfiguration(
        deviceTestEnabled: Boolean,
        buildApplicationId: String,
        runtimePackageName: String,
        filesDir: File,
        storageDirectory: File,
    ) {
        val hasDeviceTestIdentity =
            buildApplicationId == DeviceTestApplicationId || runtimePackageName == DeviceTestApplicationId
        if (!deviceTestEnabled && !hasDeviceTestIdentity) return

        check(deviceTestEnabled) { "Device-test application id requires the device-test storage profile." }
        check(buildApplicationId == DeviceTestApplicationId) {
            "Device-test build must not use the production application id."
        }
        check(runtimePackageName == DeviceTestApplicationId) {
            "Device-test runtime package does not match its isolated application id."
        }

        val expected = CalendarCoreStorageLayout.resolve(filesDir, deviceTest = true).canonicalFile
        val production = CalendarCoreStorageLayout.resolve(filesDir, deviceTest = false).canonicalFile
        val actual = storageDirectory.canonicalFile
        check(actual == expected && actual != production) {
            "Device-test runtime must use the isolated Calendar Core storage root."
        }
    }
}
