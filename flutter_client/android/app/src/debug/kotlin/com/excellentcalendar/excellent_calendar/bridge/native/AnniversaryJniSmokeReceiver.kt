package com.excellentcalendar.excellent_calendar.bridge.native

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import java.io.File

/** ADB-invoked real JNI smoke entry that is packaged only in debug builds. */
class AnniversaryJniSmokeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Action) return
        val pendingResult = goAsync()
        Thread(
            {
                try {
                    val message = runCatching {
                        AnniversaryJniSmokeRunner.run(context.applicationContext)
                    }.getOrElse { error ->
                        "FAIL ${error.stackTraceToString()}"
                    }
                    Log.i(Tag, message)
                    File(context.cacheDir, ResultFile).writeText(message)
                } finally {
                    pendingResult.finish()
                }
            },
            "anniversary-jni-smoke",
        ).start()
    }

    private companion object {
        const val Action =
            "com.excellentcalendar.excellent_calendar.ANNIVERSARY_JNI_SMOKE"
        const val ResultFile = "anniversary-jni-smoke-result.txt"
        const val Tag = "AnniversaryJniSmoke"
    }
}
