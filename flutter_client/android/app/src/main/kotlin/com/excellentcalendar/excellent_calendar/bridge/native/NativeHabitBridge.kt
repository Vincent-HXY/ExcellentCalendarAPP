package com.excellentcalendar.excellent_calendar.bridge.native

/** Narrow Kotlin access to the Habit V1 C++ boundary. */
interface NativeHabitBridge {
    fun createHabit(requestJson: String): String = unavailable()
    fun updateHabit(requestJson: String): String = unavailable()
    fun listHabits(requestJson: String): String = unavailable()
    fun getHabitDetail(requestJson: String): String = unavailable()
    fun endHabit(requestJson: String): String = unavailable()
    fun deleteHabit(requestJson: String): String = unavailable()
    fun checkInHabit(requestJson: String): String = unavailable()
    fun clearHabitCheckIn(requestJson: String): String = unavailable()
    fun listHabitDailyStatuses(requestJson: String): String = unavailable()
    fun setHabitReminder(requestJson: String): String = unavailable()
    fun reconcileHabitReminders(requestJson: String): String = unavailable()

    private fun unavailable(): Nothing = throw UnsupportedOperationException("Habit V1 bridge is unavailable.")
}

/** Frozen JNI method names expected from the final C++ integration. */
object HabitJniSymbolManifest {
    val methods: List<String> = listOf(
        "nativeCreateHabitV2",
        "nativeUpdateHabitV2",
        "nativeListHabitsV2",
        "nativeGetHabitDetailV2",
        "nativeEndHabitV2",
        "nativeDeleteHabitV2",
        "nativeCheckInHabitV2",
        "nativeClearHabitCheckInV2",
        "nativeListHabitDailyStatusesV2",
        "nativeSetHabitReminderV2",
        "nativeReconcileHabitRemindersV2",
    )
}
