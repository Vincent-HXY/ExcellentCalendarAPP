package com.excellentcalendar.excellent_calendar.android.appearance

import android.content.Context
import android.util.Log

interface AppearancePreferencesStore {
    fun getHabitProgressColor(): String
    fun updateHabitProgressColor(token: String): String
}

class AppearanceStorageException(message: String, cause: Throwable? = null) : Exception(message, cause)

class SharedPreferencesAppearanceStore(context: Context) : AppearancePreferencesStore {
    private val preferences = context.applicationContext.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
    private val lock = Any()

    override fun getHabitProgressColor(): String = synchronized(lock) {
        val persisted = try {
            preferences.getString(KeyHabitProgressColor, null)
        } catch (error: ClassCastException) {
            Log.w(LogTag, "appearance preference type was corrupted")
            return@synchronized DefaultToken
        } catch (error: RuntimeException) {
            throw AppearanceStorageException("Appearance preferences could not be read.", error)
        }
        if (persisted == null) return@synchronized DefaultToken
        if (persisted !in AllowedTokens) {
            Log.w(LogTag, "appearance preference token was corrupted")
            return@synchronized DefaultToken
        }
        persisted
    }

    override fun updateHabitProgressColor(token: String): String = synchronized(lock) {
        require(token in AllowedTokens) { "Unsupported appearance color token." }
        val persisted = try {
            preferences.edit().putString(KeyHabitProgressColor, token).commit()
        } catch (error: RuntimeException) {
            throw AppearanceStorageException("Appearance preferences could not be persisted.", error)
        }
        if (!persisted) throw AppearanceStorageException("Appearance preferences could not be persisted.")
        token
    }

    companion object {
        const val DefaultToken = "teal"
        val AllowedTokens = setOf("teal", "blue", "indigo", "green", "orange", "rose", "purple")
        private const val PreferencesName = "excellent_calendar_appearance_v1"
        private const val KeyHabitProgressColor = "habit_progress_color"
        private const val LogTag = "ExcellentCalendarAppearance"
    }
}
