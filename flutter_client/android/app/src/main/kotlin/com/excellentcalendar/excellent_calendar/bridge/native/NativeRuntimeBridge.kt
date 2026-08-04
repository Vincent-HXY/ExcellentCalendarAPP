package com.excellentcalendar.excellent_calendar.bridge.native

/** Narrow JNI surface for process runtime initialization. */
interface NativeRuntimeBridge {
    fun initializeRuntime(requestJson: String): String = throw UnsupportedOperationException("runtime.initialize is unavailable")
}

fun interface NativeRuntimeRequestProvider {
    /** Performs filesystem work lazily on the caller's controlled background thread. */
    fun createRequestJson(): String
}
