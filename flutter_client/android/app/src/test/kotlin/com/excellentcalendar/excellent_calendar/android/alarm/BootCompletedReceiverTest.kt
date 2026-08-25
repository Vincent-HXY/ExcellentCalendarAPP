package com.excellentcalendar.excellent_calendar.android.alarm

import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderScheduleTrigger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BootCompletedReceiverTest {
    @Test
    fun systemAndPermissionActionsMapToTheSharedReconciliationTriggers() {
        val cases = linkedMapOf(
            "android.intent.action.BOOT_COMPLETED" to ReminderScheduleTrigger.BootCompleted,
            "android.intent.action.MY_PACKAGE_REPLACED" to ReminderScheduleTrigger.PackageReplaced,
            "android.intent.action.TIME_SET" to ReminderScheduleTrigger.TimeChanged,
            "android.intent.action.DATE_CHANGED" to ReminderScheduleTrigger.TimeChanged,
            "android.intent.action.TIMEZONE_CHANGED" to ReminderScheduleTrigger.TimezoneChanged,
            "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED" to
                ReminderScheduleTrigger.ManualRetry,
        )

        cases.forEach { (action, expected) ->
            assertEquals(action, expected, reminderScheduleTriggerForAction(action))
        }
        assertNull(reminderScheduleTriggerForAction("com.example.UNKNOWN"))
        assertNull(reminderScheduleTriggerForAction(null))
    }
}
