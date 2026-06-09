package com.excellentcalendar.excellent_calendar.bridge.native

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeContractViolation
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract

class NativeBridgeUnavailableException(
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

fun interface NativeLibraryLoader {
    fun load()
}

class JniNativeEventBridge(
    private val storageDirectory: String? = null,
    private val libraryLoader: NativeLibraryLoader = NativeLibraryLoader {
        System.loadLibrary(NativeLibraryName)
    },
) : NativeEventBridge {
    @Volatile
    private var loadAttempted = false

    @Volatile
    private var loadFailure: Throwable? = null

    @Volatile
    private var storageInitAttempted = false

    @Volatile
    private var storageInitFailureJson: String? = null

    override fun createEvent(requestJson: String): String {
        ensureLibraryLoaded()
        ensureStorageInitialized()?.let { return it }
        return try {
            nativeCreateEvent(requestJson)
        } catch (error: UnsatisfiedLinkError) {
            throw NativeBridgeUnavailableException("JNI symbol nativeCreateEvent is unavailable.", error)
        }
    }

    override fun searchEvents(requestJson: String): String {
        ensureLibraryLoaded()
        ensureStorageInitialized()?.let { return it }
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

    external fun nativeInitializeStorage(storageDirectory: String): String

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

    private fun ensureStorageInitialized(): String? {
        val directory = storageDirectory ?: return null
        if (!storageInitAttempted) {
            synchronized(this) {
                if (!storageInitAttempted) {
                    storageInitFailureJson = initializeStorage(directory)
                    storageInitAttempted = true
                }
            }
        }
        return storageInitFailureJson
    }

    private fun initializeStorage(directory: String): String? {
        val initJson = try {
            nativeInitializeStorage(directory)
        } catch (error: UnsatisfiedLinkError) {
            throw NativeBridgeUnavailableException("JNI symbol nativeInitializeStorage is unavailable.", error)
        }
        return try {
            val parsed = NativeResultContract.fromJson(initJson) { }
            if (parsed.ok) null else initJson
        } catch (error: NativeContractViolation) {
            NativeContractJsonCodec.encodeObject(
                NativeResultContract.failure(
                    code = NativeErrorCodes.ContractValidationFailed,
                    message = error.message ?: "Native storage initialization returned malformed NativeResult.",
                    details = linkedMapOf("field" to error.field),
                ).toMap(),
            )
        }
    }

    companion object {
        const val NativeLibraryName = "excellent_calendar_native"
    }
}
