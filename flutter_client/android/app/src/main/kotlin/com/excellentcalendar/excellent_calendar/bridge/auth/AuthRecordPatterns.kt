package com.excellentcalendar.excellent_calendar.bridge.auth

/**
 * Shared validation for Refresh Token record fields (UUID + UTC date-time).
 * Used by both the file codec and the MethodChannel contract validators so
 * the rules exist in exactly one place.
 */
internal object AuthRecordPatterns {
    private val UuidPattern =
        Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
    private val UtcDateTimePattern =
        Regex("^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})(?:\\.\\d{1,6})?Z$")

    fun isUuid(value: String): Boolean = UuidPattern.matches(value)

    /** RFC 3339 UTC instant with real calendar ranges (matches the Dart parser). */
    fun isValidUtcDateTime(value: String): Boolean {
        val match = UtcDateTimePattern.matchEntire(value) ?: return false
        val year = match.groupValues[1].toInt()
        val month = match.groupValues[2].toInt()
        val day = match.groupValues[3].toInt()
        val hour = match.groupValues[4].toInt()
        val minute = match.groupValues[5].toInt()
        val second = match.groupValues[6].toInt()
        if (year < 1 || year > 9999 || month !in 1..12 || hour > 23 || minute > 59 || second > 59) {
            return false
        }
        val daysInMonth = when (month) {
            2 -> if ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0) 29 else 28
            4, 6, 9, 11 -> 30
            else -> 31
        }
        return day in 1..daysInMonth
    }
}
