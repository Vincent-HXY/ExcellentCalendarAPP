package com.excellentcalendar.excellent_calendar.bridge.native

/** Kotlin side reminder-module access to C++ Calendar Core. */
interface NativeReminderBridge {
    fun createReminder(requestJson: String): String

    fun updateReminder(requestJson: String): String

    fun cancelReminder(requestJson: String): String

    fun listReminders(requestJson: String): String

    fun getReminder(requestJson: String): String

    fun listSchedulableReminders(requestJson: String): String

    fun markReminderScheduled(requestJson: String): String

    fun markReminderSent(requestJson: String): String

    fun markReminderFailed(requestJson: String): String

    fun enableReminder(requestJson: String): String

    fun disableReminder(requestJson: String): String

    fun prepareReminderDelivery(requestJson: String): String = throw UnsupportedOperationException("reminder.prepare_delivery is unavailable")

    fun finalizeReminderDelivery(requestJson: String): String = throw UnsupportedOperationException("reminder.finalize_delivery is unavailable")

    fun planReminderRecovery(requestJson: String): String = throw UnsupportedOperationException("reminder.plan_recovery is unavailable")
}
