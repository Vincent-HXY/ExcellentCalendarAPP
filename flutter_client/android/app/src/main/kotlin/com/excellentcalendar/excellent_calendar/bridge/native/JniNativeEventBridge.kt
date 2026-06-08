package com.excellentcalendar.excellent_calendar.bridge.native

class NativeBridgeUnavailableException(
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

fun interface NativeLibraryLoader {
    fun load()
}

class JniNativeEventBridge(
    private val libraryLoader: NativeLibraryLoader = NativeLibraryLoader {
        System.loadLibrary(NativeLibraryName)
    },
) : NativeEventBridge {
    @Volatile
    private var loadAttempted = false

    @Volatile
    private var loadFailure: Throwable? = null

    override fun createEvent(requestJson: String): String {
        ensureLibraryLoaded()
        return try {
            nativeCreateEvent(requestJson)
        } catch (error: UnsatisfiedLinkError) {
            throw NativeBridgeUnavailableException("JNI symbol nativeCreateEvent is unavailable.", error)
        }
    }

    override fun searchEvents(requestJson: String): String {
        ensureLibraryLoaded()
        return try {
            nativeSearchEvents(requestJson)
        } catch (error: UnsatisfiedLinkError) {
            throw NativeBridgeUnavailableException("JNI symbol nativeSearchEvents is unavailable.", error)
        }
    }

    override fun completeEvent(requestJson: String): String {
        ensureLibraryLoaded()
        return try {
            nativeCompleteEvent(requestJson)
        } catch (error: UnsatisfiedLinkError) {
            throw NativeBridgeUnavailableException("JNI symbol nativeCompleteEvent is unavailable.", error)
        }
    }

    override fun reopenEvent(requestJson: String): String {
        ensureLibraryLoaded()
        return try {
            nativeReopenEvent(requestJson)
        } catch (error: UnsatisfiedLinkError) {
            throw NativeBridgeUnavailableException("JNI symbol nativeReopenEvent is unavailable.", error)
        }
    }

    external fun nativeCreateEvent(requestJson: String): String

    external fun nativeSearchEvents(requestJson: String): String

    external fun nativeCompleteEvent(requestJson: String): String

    external fun nativeReopenEvent(requestJson: String): String

    private fun ensureLibraryLoaded() {
        if (!loadAttempted) {
            synchronized(this) {
                if (!loadAttempted) {
                    loadFailure = try {
                        libraryLoader.load()
                        null
                    } catch (error: UnsatisfiedLinkError) {
                        error
                    } catch (error: SecurityException) {
                        error
                    }
                    loadAttempted = true
                }
            }
        }
        val failure = loadFailure
        if (failure != null) {
            throw NativeBridgeUnavailableException("Native event library is unavailable.", failure)
        }
    }

    companion object {
        const val NativeLibraryName = "excellent_calendar_native"
    }
}
