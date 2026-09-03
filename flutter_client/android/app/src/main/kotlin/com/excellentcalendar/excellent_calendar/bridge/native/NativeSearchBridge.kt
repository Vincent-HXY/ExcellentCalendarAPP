package com.excellentcalendar.excellent_calendar.bridge.native

/** Narrow Kotlin access to the one unified Search query endpoint. History never enters JNI. */
interface NativeSearchBridge {
    fun querySearch(requestJson: String): String =
        throw UnsupportedOperationException("Search bridge is unavailable.")
}

object SearchJniSymbolManifest {
    val methods: List<String> = listOf("nativeQuerySearchV2")
}
