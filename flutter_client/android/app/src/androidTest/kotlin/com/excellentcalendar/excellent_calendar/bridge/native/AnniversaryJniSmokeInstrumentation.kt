package com.excellentcalendar.excellent_calendar.bridge.native

import android.app.Activity
import android.app.Instrumentation
import android.os.Bundle
import android.util.Log

/** ADB entry point for selectable native bridge smoke runners; Anniversary remains the default target. */
class AnniversaryJniSmokeInstrumentation : Instrumentation() {
    private var smokeTarget: String? = null

    override fun onCreate(arguments: Bundle?) {
        smokeTarget = arguments?.getString(ArgumentTarget)
        super.onCreate(arguments)
        start()
    }

    override fun onStart() {
        val result = runCatching {
            when (smokeTarget) {
                null, AnniversaryTarget -> AnniversaryJniSmokeRunner.run(targetContext)
                CategoryTarget -> CategoryNativeBridgeSmokeRunner.run(targetContext)
                else -> error("Unknown native smoke target")
            }
        }

        val output = Bundle()
        result.fold(
            onSuccess = { message ->
                Log.i(Tag, message)
                output.putString(REPORT_KEY_STREAMRESULT, "$message\n")
                finish(Activity.RESULT_OK, output)
            },
            onFailure = { error ->
                val message = "FAIL ${error.stackTraceToString()}"
                Log.e(Tag, message)
                output.putString(REPORT_KEY_STREAMRESULT, "$message\n")
                finish(Activity.RESULT_CANCELED, output)
            },
        )
    }

    private companion object {
        const val Tag = "AnniversaryJniSmoke"
        const val ArgumentTarget = "target"
        const val AnniversaryTarget = "anniversary"
        const val CategoryTarget = "category"
    }
}
