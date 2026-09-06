package com.excellentcalendar.excellent_calendar.android.appearance

import android.content.Context
import android.util.Log

interface AppearancePreferencesStore {
    fun getHabitProgressColor(): String
    fun updateHabitProgressColor(token: String): String
    fun getDisplayPreferences(): DisplayPreferences
    fun updateDisplayPreferences(token: String, display: DisplayPreferences): String
}

class AppearanceStorageException(message: String, cause: Throwable? = null) : Exception(message, cause)

class SharedPreferencesAppearanceStore(context: Context) : AppearancePreferencesStore {
    private val preferences = context.applicationContext.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
    private val lock = Any()

    override fun getDisplayPreferences(): DisplayPreferences = synchronized(lock) {
        try {
            DisplayPreferences(
                preferences.getInt("display_font_scale_percent", -1).let { if (it == -1) null else it },
                preferences.getInt("display_font_weight_delta", -1),
                preferences.getString("display_font_family", "system")!!,
            )
        } catch (error: ClassCastException) {
            Log.w(LogTag, "display preferences type was corrupted")
            DisplayPreferences()
        } catch (error: IllegalArgumentException) {
            Log.w(LogTag, "display preferences value was corrupted")
            DisplayPreferences()
        } catch (error: RuntimeException) {
            throw AppearanceStorageException("Display preferences could not be read.", error)
        }
    }

    override fun updateDisplayPreferences(token: String, display: DisplayPreferences): String = synchronized(lock) {
        require(token in AllowedTokens)
        val persisted = try {
            preferences.edit()
                .putString(KeyHabitProgressColor, token)
                .putInt("display_font_scale_percent", display.fontScalePercent ?: -1)
                .putInt("display_font_weight_delta", display.fontWeightDelta)
                .putString("display_font_family", display.fontFamily)
                .commit()
        } catch (error: RuntimeException) {
            throw AppearanceStorageException("Display preferences could not be persisted.", error)
        }
        if (!persisted) throw AppearanceStorageException("Display preferences could not be persisted.")
        token
    }

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
