package com.excellentcalendar.excellent_calendar.android.alarm

import android.content.Context
import android.util.Log
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderListResponseContract
import com.excellentcalendar.excellent_calendar.bridge.native.NativeReminderBridge

/** Cancels per-reminder PendingIntents left by the pre-dispatcher implementation. */
object LegacyReminderAlarmMigration {
    fun runIfNeeded(context: Context, nativeBridge: NativeReminderBridge) {
        val appContext = context.applicationContext
        val preferences = appContext.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
        if (preferences.getInt(MigrationKey, 0) >= MigrationVersion) return
        val scheduler = AlarmManagerReminderScheduler(appContext)
        var page = 1
        try {
            do {
                val request = linkedMapOf<String, Any?>(
                    "include_deleted" to true,
                    "pagination" to linkedMapOf(
                        "page" to page,
                        "page_size" to PageSize,
                        "cursor" to null,
                        "sort_by" to null,
                        "sort_direction" to "asc",
                    ),
                    "sort_by" to "remind_at",
                    "sort_direction" to "asc",
                )
                val listed = NativeResultContract.fromJson(
                    nativeBridge.listReminders(NativeContractJsonCodec.encodeObject(request)),
                    ReminderListResponseContract::validate,
                )
                if (!listed.ok) return
                @Suppress("UNCHECKED_CAST")
                val data = listed.data as Map<String, Any?>
                @Suppress("UNCHECKED_CAST")
                val items = data["items"] as List<Map<String, Any?>>
                items.map(ReminderContract::fromData).forEach { scheduler.cancel(it.id) }
                @Suppress("UNCHECKED_CAST")
                val pagination = data["pagination"] as Map<String, Any?>
                val hasMore = pagination["has_more"] as Boolean
                if (!hasMore) break
                page += 1
            } while (true)
            preferences.edit().putInt(MigrationKey, MigrationVersion).apply()
        } catch (error: Throwable) {
            Log.w(LogTag, "legacy alarm migration failed type=${error.javaClass.simpleName}")
        }
    }

    private const val PreferencesName = "reminder_alarm_migration"
    private const val MigrationKey = "dispatcher_version"
    private const val MigrationVersion = 1
    private const val PageSize = 200
    private const val LogTag = "ExcellentCalendarQueue"
}
