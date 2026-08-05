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

/** One bridge framework with a strictly selected native contract profile. */
class JniNativeCalendarCoreBridge(
    val profile: NativeContractProfile = NativeContractProfile.V1,
    private val storageDirectory: String? = null,
    private val runtimeRequestProvider: NativeRuntimeRequestProvider? = null,
    private val libraryLoader: NativeLibraryLoader = NativeLibraryLoader {
        System.loadLibrary(NativeLibraryName)
    },
    private val runtimeInitializer: ((String) -> String)? = null,
) : NativeCalendarCoreBridge {
    @Volatile private var loadAttempted = false
    @Volatile private var loadFailure: Throwable? = null
    @Volatile private var runtimeInitAttempted = false
    @Volatile private var runtimeInitFailureJson: String? = null

    override fun initializeRuntime(requestJson: String): String {
        ensureLibraryLoaded()
        return callNative(if (profile == NativeContractProfile.V2) "nativeInitializeRuntimeV2" else "nativeInitializeStorage") {
            if (profile == NativeContractProfile.V2) nativeInitializeRuntimeV2(requestJson)
            else nativeInitializeStorage(requestJson)
        }
    }

    override fun resolveLocalDateTime(requestJson: String) = v2Only("nativeResolveLocalDateTimeV2") {
        nativeResolveLocalDateTimeV2(requestJson)
    }

    override fun localizeInstants(requestJson: String) = v2Only("nativeLocalizeInstantsV2") {
        nativeLocalizeInstantsV2(requestJson)
    }

    override fun createEvent(requestJson: String) = callWithRuntime("nativeCreateEvent") {
        if (profile == NativeContractProfile.V2) nativeCreateEventV2(requestJson) else nativeCreateEvent(requestJson)
    }

    override fun updateEvent(requestJson: String) = callWithRuntime("nativeUpdateEvent") {
        if (profile == NativeContractProfile.V2) nativeUpdateEventV2(requestJson) else nativeUpdateEvent(requestJson)
    }

    override fun deleteEvent(requestJson: String) = callWithRuntime("nativeDeleteEvent") {
        if (profile == NativeContractProfile.V2) nativeDeleteEventV2(requestJson) else nativeDeleteEvent(requestJson)
    }

    override fun searchEvents(requestJson: String) = callWithRuntime("nativeSearchEvents") {
        if (profile == NativeContractProfile.V2) nativeSearchEventsV2(requestJson) else nativeSearchEvents(requestJson)
    }

    override fun getEventDetail(requestJson: String): String = v2Only("nativeGetEventDetailV2") {
        nativeGetEventDetailV2(requestJson)
    }

    override fun completeEvent(requestJson: String) = callWithRuntime("nativeCompleteEvent") {
        if (profile == NativeContractProfile.V2) nativeCompleteEventV2(requestJson) else nativeCompleteEvent(requestJson)
    }

    override fun reopenEvent(requestJson: String) = callWithRuntime("nativeReopenEvent") {
        if (profile == NativeContractProfile.V2) nativeReopenEventV2(requestJson) else nativeReopenEvent(requestJson)
    }

    override fun listEventOccurrences(requestJson: String) = v2Only("nativeListEventOccurrencesV2") {
        nativeListEventOccurrencesV2(requestJson)
    }

    override fun completeEventOccurrence(requestJson: String) = v2Only("nativeCompleteEventOccurrenceV2") {
        nativeCompleteEventOccurrenceV2(requestJson)
    }

    override fun reopenEventOccurrence(requestJson: String) = v2Only("nativeReopenEventOccurrenceV2") {
        nativeReopenEventOccurrenceV2(requestJson)
    }

    override fun skipEventOccurrence(requestJson: String) = v2Only("nativeSkipEventOccurrenceV2") {
        nativeSkipEventOccurrenceV2(requestJson)
    }

    override fun cancelEventOccurrence(requestJson: String) = v2Only("nativeCancelEventOccurrenceV2") {
        nativeCancelEventOccurrenceV2(requestJson)
    }

    override fun completeEventSeries(requestJson: String) = v2Only("nativeCompleteEventSeriesV2") {
        nativeCompleteEventSeriesV2(requestJson)
    }

    override fun reopenEventSeries(requestJson: String) = v2Only("nativeReopenEventSeriesV2") {
        nativeReopenEventSeriesV2(requestJson)
    }

    override fun cancelEventSeries(requestJson: String) = v2Only("nativeCancelEventSeriesV2") {
        nativeCancelEventSeriesV2(requestJson)
    }

    override fun createReminder(requestJson: String) = callWithRuntime("nativeCreateReminder") {
        if (profile == NativeContractProfile.V2) nativeCreateReminderV2(requestJson) else nativeCreateReminder(requestJson)
    }

    override fun updateReminder(requestJson: String) = callWithRuntime("nativeUpdateReminder") {
        if (profile == NativeContractProfile.V2) nativeUpdateReminderV2(requestJson) else nativeUpdateReminder(requestJson)
    }

    override fun cancelReminder(requestJson: String) = callWithRuntime("nativeCancelReminder") {
        if (profile == NativeContractProfile.V2) nativeCancelReminderV2(requestJson) else nativeCancelReminder(requestJson)
    }

    override fun listReminders(requestJson: String) = callWithRuntime("nativeListReminders") {
        if (profile == NativeContractProfile.V2) nativeListRemindersV2(requestJson) else nativeListReminders(requestJson)
    }

    override fun getReminder(requestJson: String) = callWithRuntime("nativeGetReminder") {
        if (profile == NativeContractProfile.V2) nativeGetReminderV2(requestJson) else nativeGetReminder(requestJson)
    }

    override fun listSchedulableReminders(requestJson: String) = callWithRuntime("nativeListSchedulableReminders") {
        if (profile == NativeContractProfile.V2) nativeListSchedulableRemindersV2(requestJson)
        else nativeListSchedulableReminders(requestJson)
    }

    override fun markReminderScheduled(requestJson: String) = callWithRuntime("nativeMarkReminderScheduled") {
        if (profile == NativeContractProfile.V2) nativeMarkReminderScheduledV2(requestJson)
        else nativeMarkReminderScheduled(requestJson)
    }

    override fun markReminderSent(requestJson: String): String = if (profile == NativeContractProfile.V1) {
        callWithRuntime("nativeMarkReminderSent") { nativeMarkReminderSent(requestJson) }
    } else unsupported("reminder.mark_sent")

    override fun markReminderFailed(requestJson: String): String = if (profile == NativeContractProfile.V1) {
        callWithRuntime("nativeMarkReminderFailed") { nativeMarkReminderFailed(requestJson) }
    } else unsupported("reminder.mark_failed")

    override fun enableReminder(requestJson: String) = callWithRuntime("nativeEnableReminder") {
        if (profile == NativeContractProfile.V2) nativeEnableReminderV2(requestJson) else nativeEnableReminder(requestJson)
    }

    override fun disableReminder(requestJson: String) = callWithRuntime("nativeDisableReminder") {
        if (profile == NativeContractProfile.V2) nativeDisableReminderV2(requestJson) else nativeDisableReminder(requestJson)
    }

    override fun prepareReminderDelivery(requestJson: String) = v2Only("nativePrepareReminderDeliveryV2") {
        nativePrepareReminderDeliveryV2(requestJson)
    }

    override fun finalizeReminderDelivery(requestJson: String) = v2Only("nativeFinalizeReminderDeliveryV2") {
        nativeFinalizeReminderDeliveryV2(requestJson)
    }

    override fun planReminderRecovery(requestJson: String) = v2Only("nativePlanReminderRecoveryV2") {
        nativePlanReminderRecoveryV2(requestJson)
    }

    override fun createNotification(requestJson: String): String = if (profile == NativeContractProfile.V1) {
        callWithRuntime("nativeCreateNotification") { nativeCreateNotification(requestJson) }
    } else unsupported("notification.create")

    override fun consumeReminderAfterDelivery(requestJson: String): String = if (profile == NativeContractProfile.V1) {
        callWithRuntime("nativeConsumeReminderAfterDelivery") { nativeConsumeReminderAfterDelivery(requestJson) }
    } else unsupported("reminder.consume_after_delivery")

    private inline fun v2Only(symbol: String, call: () -> String): String {
        if (profile != NativeContractProfile.V2) return unsupported(symbol)
        return callWithRuntime(symbol, call)
    }

    private inline fun callWithRuntime(symbol: String, call: () -> String): String {
        ensureLibraryLoaded()
        ensureRuntimeInitialized()?.let { return it }
        return callNative(symbol, call)
    }

    private inline fun callNative(symbol: String, call: () -> String): String = try {
        call()
    } catch (error: UnsatisfiedLinkError) {
        throw NativeBridgeUnavailableException("JNI symbol $symbol is unavailable.", error)
    }

    private fun ensureLibraryLoaded() {
        if (!loadAttempted) synchronized(this) {
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
        loadFailure?.let { throw NativeBridgeUnavailableException("Native calendar core library is unavailable.", it) }
    }

    private fun ensureRuntimeInitialized(): String? {
        if (profile == NativeContractProfile.V1 && storageDirectory == null) return null
        if (!runtimeInitAttempted) synchronized(this) {
            if (!runtimeInitAttempted) {
                val attempt = initializeConfiguredRuntime()
                runtimeInitFailureJson = attempt.failureJson
                runtimeInitAttempted = attempt.failureJson == null || !attempt.retryable
            }
        }
        return runtimeInitFailureJson
    }

    private fun initializeConfiguredRuntime(): RuntimeInitializationAttempt {
        val request = if (profile == NativeContractProfile.V2) {
            runtimeRequestProvider?.createRequestJson()
                ?: return RuntimeInitializationAttempt(
                    localFailure("Calendar Core v2 runtime request provider is unavailable."),
                    retryable = false,
                )
        } else {
            storageDirectory ?: return RuntimeInitializationAttempt(failureJson = null, retryable = false)
        }
        val initJson = runtimeInitializer?.invoke(request) ?: initializeRuntime(request)
        return try {
            val parsed = NativeResultContract.fromJson(
                initJson,
                dataValidator = { data ->
                    if (profile == NativeContractProfile.V2) validateV2RuntimeResponse(data)
                },
                expectedContractVersion = profile.contractVersion,
            )
            if (parsed.ok) {
                RuntimeInitializationAttempt(failureJson = null, retryable = false)
            } else {
                RuntimeInitializationAttempt(initJson, retryable = parsed.error?.retryable == true)
            }
        } catch (error: NativeContractViolation) {
            RuntimeInitializationAttempt(
                localFailure(error.message ?: "Native runtime initialization returned malformed NativeResult.", error.field),
                retryable = false,
            )
        }
    }

    private data class RuntimeInitializationAttempt(
        val failureJson: String?,
        val retryable: Boolean,
    )

    private fun validateV2RuntimeResponse(data: Any?) {
        if (data !is Map<*, *> || data["initialized"] != true || data["storage_format_version"] != 2 || data["tzdb_version"] != BundledTzdbExtractor.Version) {
            throw NativeContractViolation("Runtime v2 initialization response is malformed.", "data")
        }
    }

    private fun unsupported(operation: String): String = NativeContractJsonCodec.encodeObject(
        NativeResultContract.failure(
            code = NativeErrorCodes.FeatureNotImplemented,
            message = "$operation is unavailable for Native Contract ${profile.contractVersion}.",
            contractVersion = profile.contractVersion,
        ).toMap(),
    )

    private fun localFailure(message: String, field: String? = null): String = NativeContractJsonCodec.encodeObject(
        NativeResultContract.failure(
            code = NativeErrorCodes.ContractValidationFailed,
            message = message,
            details = field?.let { linkedMapOf("field" to it) },
            contractVersion = profile.contractVersion,
        ).toMap(),
    )

    external fun nativeInitializeStorage(storageDirectory: String): String
    external fun nativeInitializeRuntimeV2(requestJson: String): String
    external fun nativeResolveLocalDateTimeV2(requestJson: String): String
    external fun nativeLocalizeInstantsV2(requestJson: String): String
    external fun nativeCreateEvent(requestJson: String): String
    external fun nativeCreateEventV2(requestJson: String): String
    external fun nativeUpdateEvent(requestJson: String): String
    external fun nativeUpdateEventV2(requestJson: String): String
    external fun nativeDeleteEvent(requestJson: String): String
    external fun nativeDeleteEventV2(requestJson: String): String
    external fun nativeSearchEvents(requestJson: String): String
    external fun nativeSearchEventsV2(requestJson: String): String
    external fun nativeGetEventDetailV2(requestJson: String): String
    external fun nativeCompleteEvent(requestJson: String): String
    external fun nativeCompleteEventV2(requestJson: String): String
    external fun nativeReopenEvent(requestJson: String): String
    external fun nativeReopenEventV2(requestJson: String): String
    external fun nativeListEventOccurrencesV2(requestJson: String): String
    external fun nativeCompleteEventOccurrenceV2(requestJson: String): String
    external fun nativeReopenEventOccurrenceV2(requestJson: String): String
    external fun nativeSkipEventOccurrenceV2(requestJson: String): String
    external fun nativeCancelEventOccurrenceV2(requestJson: String): String
    external fun nativeCompleteEventSeriesV2(requestJson: String): String
    external fun nativeReopenEventSeriesV2(requestJson: String): String
    external fun nativeCancelEventSeriesV2(requestJson: String): String
    external fun nativeCreateReminder(requestJson: String): String
    external fun nativeCreateReminderV2(requestJson: String): String
    external fun nativeUpdateReminder(requestJson: String): String
    external fun nativeUpdateReminderV2(requestJson: String): String
    external fun nativeCancelReminder(requestJson: String): String
    external fun nativeCancelReminderV2(requestJson: String): String
    external fun nativeListReminders(requestJson: String): String
    external fun nativeListRemindersV2(requestJson: String): String
    external fun nativeGetReminder(requestJson: String): String
    external fun nativeGetReminderV2(requestJson: String): String
    external fun nativeListSchedulableReminders(requestJson: String): String
    external fun nativeListSchedulableRemindersV2(requestJson: String): String
    external fun nativeMarkReminderScheduled(requestJson: String): String
    external fun nativeMarkReminderScheduledV2(requestJson: String): String
    external fun nativeMarkReminderSent(requestJson: String): String
    external fun nativeMarkReminderFailed(requestJson: String): String
    external fun nativeEnableReminder(requestJson: String): String
    external fun nativeEnableReminderV2(requestJson: String): String
    external fun nativeDisableReminder(requestJson: String): String
    external fun nativeDisableReminderV2(requestJson: String): String
    external fun nativePrepareReminderDeliveryV2(requestJson: String): String
    external fun nativeFinalizeReminderDeliveryV2(requestJson: String): String
    external fun nativePlanReminderRecoveryV2(requestJson: String): String
    external fun nativeCreateNotification(requestJson: String): String
    external fun nativeConsumeReminderAfterDelivery(requestJson: String): String

    companion object {
        const val NativeLibraryName = "excellent_calendar_native"
    }
}
