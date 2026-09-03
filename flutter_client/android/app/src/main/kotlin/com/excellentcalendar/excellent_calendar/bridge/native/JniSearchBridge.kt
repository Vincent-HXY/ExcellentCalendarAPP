package com.excellentcalendar.excellent_calendar.bridge.native

/** Production Search adapter. Runtime ownership and native loading stay in the aggregate bridge. */
class JniSearchBridge internal constructor(
    private val invoke: (symbol: String, requestJson: String) -> String,
) : NativeSearchBridge {
    override fun querySearch(requestJson: String): String = invoke(SearchJniSymbolManifest.methods.single(), requestJson)
}
