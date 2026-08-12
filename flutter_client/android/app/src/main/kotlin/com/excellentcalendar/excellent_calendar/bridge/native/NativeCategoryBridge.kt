package com.excellentcalendar.excellent_calendar.bridge.native

/** Narrow Kotlin access to the C++ Category Contract v2 boundary. */
interface NativeCategoryBridge {
    fun listCategories(requestJson: String): String

    fun createCategory(requestJson: String): String
}
