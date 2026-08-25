package com.excellentcalendar.excellent_calendar.android.ring

import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

internal fun ringUtcNow(): String = ringUtcFromMillis(System.currentTimeMillis())

internal fun ringUtcFromMillis(epochMillis: Long): String = utcFormat("yyyy-MM-dd'T'HH:mm:ss'Z'").format(Date(epochMillis))

internal fun ringUtcToMillis(value: String): Long {
    val normalized = value.replace(Regex("\\.(\\d{3})\\d+(?=Z|[+-]\\d{2}:?\\d{2}$)")) {
        ".${it.groupValues[1]}"
    }
    val patterns = listOf(
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",
        "yyyy-MM-dd'T'HH:mm:ssXXX",
        "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
        "yyyy-MM-dd'T'HH:mm:ss'Z'",
    )
    for (pattern in patterns) {
        val parser = utcFormat(pattern)
        val position = ParsePosition(0)
        val parsed = parser.parse(normalized, position)
        if (parsed != null && position.index == normalized.length) return parsed.time
    }
    error("Malformed UTC timestamp.")
}

private fun utcFormat(pattern: String): SimpleDateFormat = SimpleDateFormat(pattern, Locale.US).apply {
    isLenient = false
    timeZone = TimeZone.getTimeZone("UTC")
}
