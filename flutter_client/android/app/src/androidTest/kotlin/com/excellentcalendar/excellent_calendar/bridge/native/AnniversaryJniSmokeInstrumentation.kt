package com.excellentcalendar.excellent_calendar.bridge.native

import android.app.Activity
import android.app.Instrumentation
import android.os.Bundle
import android.util.Log
import com.excellentcalendar.excellent_calendar.android.search.SearchHistoryDeviceSmokeRunner

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
                HabitTarget -> HabitJniSmokeRunner.run(targetContext)
                CalendarTarget -> CalendarJniSmokeRunner.run(targetContext)
                CalendarSeededTarget -> CalendarSeededIntegrationSmokeRunner.run(targetContext)
                SearchSeededTarget -> SearchSeededIntegrationSmokeRunner.run(targetContext)
                SearchHistoryPrepareTarget -> SearchHistoryDeviceSmokeRunner.prepareInterruptedWrite(targetContext)
                SearchHistoryVerifyTarget -> SearchHistoryDeviceSmokeRunner.verifyRestartRecovery(targetContext)
                RingTarget -> RingDeviceAcceptanceSmokeRunner.runQuick(targetContext)
                RingFiveMinuteTarget -> RingDeviceAcceptanceSmokeRunner.runFiveMinute(targetContext)
                RingRestartPrepareTarget -> RingDeviceAcceptanceSmokeRunner.prepareRestart(targetContext)
                RingRestartVerifyTarget -> RingDeviceAcceptanceSmokeRunner.verifyRestart(targetContext)
                AnniversaryAlarmPrepareTarget -> AnniversaryDeviceAcceptanceSmokeRunner.prepareAlarm(targetContext)
                AnniversaryAlarmVerifyTarget -> AnniversaryDeviceAcceptanceSmokeRunner.verifyAlarm(targetContext)
                HabitFakeTarget -> HabitFakeSmokeRunner.run(targetContext)
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
        const val HabitTarget = "habit"
        const val CalendarTarget = "calendar"
        const val CalendarSeededTarget = "calendar_seeded"
        const val SearchSeededTarget = "search_seeded"
        const val SearchHistoryPrepareTarget = "search_history_prepare"
        const val SearchHistoryVerifyTarget = "search_history_verify"
        const val RingTarget = "ring"
        const val RingFiveMinuteTarget = "ring_five_minute"
        const val RingRestartPrepareTarget = "ring_restart_prepare"
        const val RingRestartVerifyTarget = "ring_restart_verify"
        const val AnniversaryAlarmPrepareTarget = "anniversary_alarm_prepare"
        const val AnniversaryAlarmVerifyTarget = "anniversary_alarm_verify"
        const val HabitFakeTarget = "habit_fake"
    }
}
