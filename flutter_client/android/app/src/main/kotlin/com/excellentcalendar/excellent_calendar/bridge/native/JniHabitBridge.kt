package com.excellentcalendar.excellent_calendar.bridge.native

/** Production Habit adapter. Runtime ownership and native loading remain in the aggregate bridge. */
class JniHabitBridge internal constructor(
    private val invoke: (symbol: String, requestJson: String) -> String,
) : NativeHabitBridge {
    override fun createHabit(requestJson: String) = invoke("nativeCreateHabitV2", requestJson)
    override fun updateHabit(requestJson: String) = invoke("nativeUpdateHabitV2", requestJson)
    override fun listHabits(requestJson: String) = invoke("nativeListHabitsV2", requestJson)
    override fun getHabitDetail(requestJson: String) = invoke("nativeGetHabitDetailV2", requestJson)
    override fun endHabit(requestJson: String) = invoke("nativeEndHabitV2", requestJson)
    override fun deleteHabit(requestJson: String) = invoke("nativeDeleteHabitV2", requestJson)
    override fun checkInHabit(requestJson: String) = invoke("nativeCheckInHabitV2", requestJson)
    override fun clearHabitCheckIn(requestJson: String) = invoke("nativeClearHabitCheckInV2", requestJson)
    override fun listHabitDailyStatuses(requestJson: String) = invoke("nativeListHabitDailyStatusesV2", requestJson)
    override fun setHabitReminder(requestJson: String) = invoke("nativeSetHabitReminderV2", requestJson)
    override fun reconcileHabitReminders(requestJson: String) = invoke("nativeReconcileHabitRemindersV2", requestJson)
}
