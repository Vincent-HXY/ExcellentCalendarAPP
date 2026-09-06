package com.excellentcalendar.excellent_calendar.android.appearance

data class DisplayPreferences(
    val fontScalePercent: Int? = null,
    val fontWeightDelta: Int = -1,
    val fontFamily: String = "system",
) {
    init {
        require(fontScalePercent == null || fontScalePercent in 80..150)
        require(fontWeightDelta in -1..2)
        require(fontFamily in Families)
    }

    companion object {
        val Families = setOf("system", "noto_sans_sc", "noto_serif_sc")
    }
}
