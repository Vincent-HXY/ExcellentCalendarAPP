package com.excellentcalendar.excellent_calendar.bridge.native

import android.content.Context
import java.io.File

object AndroidNativeBridgeFactory {
    fun create(context: Context): JniNativeEventBridge {
        val storageDirectory = File(
            context.applicationContext.filesDir,
            "local_storage/test_storage_json",
        )
        return JniNativeEventBridge(storageDirectory = storageDirectory.absolutePath)
    }
}
