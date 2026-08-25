package com.excellentcalendar.excellent_calendar.bridge.channel

import com.excellentcalendar.excellent_calendar.android.ring.RingRuntime
import com.excellentcalendar.excellent_calendar.bridge.contract.RingRequestContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.native.NativeBridgeUnavailableException
import com.excellentcalendar.excellent_calendar.bridge.native.NativeContractProfile
import com.excellentcalendar.excellent_calendar.bridge.ring.RingMethodOrchestrator
import io.flutter.plugin.common.MethodCall

internal class RingMethodHandler(
    private val contractProfile: NativeContractProfile,
    private val nativeExecutor: NativeCallExecutor,
    private val runtime: RingRuntime?,
    private val orchestrator: RingMethodOrchestrator?,
) : ChannelMethodHandler {
    override val methods = setOf(
        NativeMethodChannelHandler.MethodRingGetState,
        NativeMethodChannelHandler.MethodRingPickRingtone,
        NativeMethodChannelHandler.MethodRingUpdateSettings,
        NativeMethodChannelHandler.MethodRingTest,
        NativeMethodChannelHandler.MethodRingStopActive,
        NativeMethodChannelHandler.MethodRingSnoozeActive,
        NativeMethodChannelHandler.MethodRingCompleteItem,
    )

    override fun handle(call: MethodCall, completion: SingleCompletion) {
        if (contractProfile != NativeContractProfile.V2) return completion.notImplemented()
        when (call.method) {
            NativeMethodChannelHandler.MethodRingGetState -> {
                if (!nativeExecutor.validateEmptyRequest(call, completion)) return
                nativeExecutor.executeLocal(call.method, completion) { requireRuntime(call.method).state() }
            }
            NativeMethodChannelHandler.MethodRingPickRingtone -> pickRingtone(call, completion)
            NativeMethodChannelHandler.MethodRingUpdateSettings -> {
                val request = nativeExecutor.parse(call, completion, RingRequestContracts::updateSettings) ?: return
                nativeExecutor.executeLocal(call.method, completion) {
                    requireRuntime(call.method).updateSettings(request.expectedSettingsRevision, request.strongReminderEnabled)
                }
            }
            NativeMethodChannelHandler.MethodRingTest -> {
                val request = nativeExecutor.parse(call, completion, RingRequestContracts::test) ?: return
                nativeExecutor.executeLocal(call.method, completion) {
                    requireRuntime(call.method).test(request.expectedSettingsRevision, request.action == "start")
                }
            }
            NativeMethodChannelHandler.MethodRingStopActive -> {
                val request = nativeExecutor.parse(call, completion, RingRequestContracts::activeItems) ?: return
                nativeExecutor.executeLocal(call.method, completion) { requireRuntime(call.method).stopActive(request) }
            }
            NativeMethodChannelHandler.MethodRingSnoozeActive -> {
                val request = nativeExecutor.parse(call, completion, RingRequestContracts::activeItems) ?: return
                nativeExecutor.executeOperation(call.method, completion) { requireRuntime(call.method).snoozeActive(request) }
            }
            NativeMethodChannelHandler.MethodRingCompleteItem -> {
                val request = nativeExecutor.parse(call, completion, RingRequestContracts::completeItem) ?: return
                nativeExecutor.executeOperation(call.method, completion) { requireRuntime(call.method).completeItem(request) }
            }
            else -> completion.notImplemented()
        }
    }

    private fun pickRingtone(call: MethodCall, completion: SingleCompletion) {
        val request = nativeExecutor.parse(call, completion, RingRequestContracts::settingsRevision) ?: return
        try {
            requireOrchestrator(call.method).pickRingtone(request) {
                nativeExecutor.complete(call.method, completion, it)
            }
        } catch (error: Throwable) {
            nativeExecutor.completeInternalFailure(call.method, completion, error)
        }
    }

    private fun requireRuntime(method: String): RingRuntime = runtime
        ?: throw NativeBridgeUnavailableException("Ring runtime is not configured for $method.")

    private fun requireOrchestrator(method: String): RingMethodOrchestrator = orchestrator
        ?: throw NativeBridgeUnavailableException("Ring Activity orchestration is not configured for $method.")
}
