package com.excellentcalendar.excellent_calendar.bridge.contract

internal object AppearanceContracts {
    fun update(arguments: Any?): String {
        val request = V2ContractPrimitives.request(arguments, "UpdateLocalAppearanceRequest") { map ->
            V2ContractPrimitives.requireExactFields(map, setOf("habit_progress_color"), "UpdateLocalAppearanceRequest")
            ContractValidators.requireString(map, "habit_progress_color", "UpdateLocalAppearanceRequest", nonEmpty = true)
        }
        return request.value.getValue("habit_progress_color") as String
    }

    fun response(token: String): Map<String, Any?> {
        if (token !in com.excellentcalendar.excellent_calendar.android.appearance.SharedPreferencesAppearanceStore.AllowedTokens) {
            throw NativeContractViolation("LocalAppearanceResponse contains an invalid token.", "habit_progress_color")
        }
        return linkedMapOf("habit_progress_color" to token)
    }
}
