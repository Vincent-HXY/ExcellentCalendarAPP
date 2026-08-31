package com.excellentcalendar.excellent_calendar.bridge.native

import android.content.ComponentName
import android.content.Context
import com.excellentcalendar.excellent_calendar.android.appearance.SharedPreferencesAppearanceStore
import com.excellentcalendar.excellent_calendar.android.habit.HabitNotificationActionReceiver
import com.excellentcalendar.excellent_calendar.bridge.contract.HabitContracts

/** Device-side Kotlin-owned smoke. It deliberately does not call unresolved production Habit JNI. */
object HabitFakeSmokeRunner {
    fun run(context: Context): String {
        val preferences = context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
        preferences.edit().clear().commit().also { check(it) }
        try {
            val store = SharedPreferencesAppearanceStore(context)
            check(store.getHabitProgressColor() == "teal")
            SharedPreferencesAppearanceStore.AllowedTokens.forEach { token ->
                check(store.updateHabitProgressColor(token) == token)
                check(SharedPreferencesAppearanceStore(context).getHabitProgressColor() == token)
            }
            preferences.edit().putString(KeyColor, "corrupted").commit().also { check(it) }
            check(SharedPreferencesAppearanceStore(context).getHabitProgressColor() == "teal")

            val observed = mutableListOf<String>()
            val adapter = JniHabitBridge { symbol, request -> observed += symbol; request }
            listOf<(String) -> String>(
                adapter::createHabit, adapter::updateHabit, adapter::listHabits, adapter::getHabitDetail,
                adapter::endHabit, adapter::deleteHabit, adapter::checkInHabit, adapter::clearHabitCheckIn,
                adapter::listHabitDailyStatuses, adapter::setHabitReminder, adapter::reconcileHabitReminders,
            ).forEach { check(it("fixture") == "fixture") }
            check(observed == HabitJniSymbolManifest.methods)

            val payload = linkedMapOf<String, Any?>(
                "action_id" to "11111111-1111-4111-8111-111111111111",
                "action_type" to "complete",
                "habit_id" to "22222222-2222-4222-8222-222222222222",
                "check_date" to "2026-08-28",
                "occurrence_key" to "33333333-3333-4333-8333-333333333333",
                "reminder_id" to "44444444-4444-4444-8444-444444444444",
                "delivery_id" to "55555555-5555-4555-8555-555555555555",
            )
            HabitContracts.actionPayload(payload)
            val command = HabitContracts.notificationActionCommand(payload, "Asia/Shanghai").value
            check(command["source"] == "notification_action")
            check(command["completed_count_hundredths"] == null)

            @Suppress("DEPRECATION")
            val info = context.packageManager.getReceiverInfo(
                ComponentName(context, HabitNotificationActionReceiver::class.java),
                0,
            )
            check(!info.exported)
            return "PASS Habit Kotlin Fake smoke: appearance persistence/corruption, 11 symbols, action command, receiver boundary"
        } finally {
            preferences.edit().clear().commit()
        }
    }

    private const val PreferencesName = "excellent_calendar_appearance_v1"
    private const val KeyColor = "habit_progress_color"
}
