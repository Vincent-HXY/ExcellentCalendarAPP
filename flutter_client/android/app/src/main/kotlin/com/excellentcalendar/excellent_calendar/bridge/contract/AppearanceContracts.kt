package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.android.appearance.DisplayPreferences

internal object AppearanceContracts {
    fun update(arguments: Any?): String {
        val request = V2ContractPrimitives.request(arguments, "UpdateLocalAppearanceRequest") { map ->
            if (map.keys.any { it !in setOf("habit_progress_color", "display") }) {
                throw NativeContractViolation("Unknown appearance field.", "UpdateLocalAppearanceRequest")
            }
            ContractValidators.requireString(map, "habit_progress_color", "UpdateLocalAppearanceRequest", nonEmpty = true)
            if (map.containsKey("display")) parseDisplay(map["display"])
        }
        return request.value.getValue("habit_progress_color") as String
    }

    fun displayUpdate(arguments: Any?): DisplayPreferences? {
        val map = V2ContractPrimitives.objectMap(arguments, "UpdateLocalAppearanceRequest")
        return if (map.containsKey("display")) parseDisplay(map["display"]) else null
    }

    fun parseDisplay(value: Any?): DisplayPreferences {
        val map = V2ContractPrimitives.objectMap(value, "display")
        V2ContractPrimitives.requireExactFields(map, setOf("font_scale_percent", "font_weight_delta", "font_family"), "display")
        V2ContractPrimitives.nullableInteger(map, "font_scale_percent", "display")
        val scale = map["font_scale_percent"]?.let { V2ContractPrimitives.integerValue(it)!! }
        val weight = V2ContractPrimitives.integerValue(map["font_weight_delta"])
        val family = map["font_family"]
        if ((scale != null && scale !in 80L..150L) || weight == null || weight !in -1L..2L || family !in DisplayPreferences.Families) {
            throw NativeContractViolation("Invalid display preferences.", "display")
        }
        return DisplayPreferences(scale?.toInt(), weight.toInt(), family as String)
    }

    fun response(token: String, display: DisplayPreferences = DisplayPreferences()): Map<String, Any?> {
        if (token !in com.excellentcalendar.excellent_calendar.android.appearance.SharedPreferencesAppearanceStore.AllowedTokens) {
            throw NativeContractViolation("LocalAppearanceResponse contains an invalid token.", "habit_progress_color")
        }
        return linkedMapOf("habit_progress_color" to token, "display" to linkedMapOf(
            "font_scale_percent" to display.fontScalePercent,
            "font_weight_delta" to display.fontWeightDelta,
            "font_family" to display.fontFamily,
        ))
    }
}
