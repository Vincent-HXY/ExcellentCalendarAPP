package com.excellentcalendar.excellent_calendar.bridge.channel

import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.RuntimeTimezoneRequestContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.RuntimeTimezoneResponseContracts
import com.excellentcalendar.excellent_calendar.bridge.native.NativeContractProfile
import com.excellentcalendar.excellent_calendar.bridge.native.NativeRuntimeBridge
import com.excellentcalendar.excellent_calendar.bridge.runtime.DeviceTimezoneProvider
import io.flutter.plugin.common.MethodCall

internal class RuntimeMethodHandler(
    private val nativeBridge: NativeRuntimeBridge,
    private val contractProfile: NativeContractProfile,
    private val nativeExecutor: NativeCallExecutor,
    private val deviceTimezoneProvider: DeviceTimezoneProvider,
) : ChannelMethodHandler {
    override val methods = setOf(
        NativeMethodChannelHandler.MethodRuntimeDeviceTimezone,
        NativeMethodChannelHandler.MethodRuntimeResolveLocalDateTime,
        NativeMethodChannelHandler.MethodRuntimeLocalizeInstants,
    )

    override fun handle(call: MethodCall, completion: SingleCompletion) {
        when (call.method) {
            NativeMethodChannelHandler.MethodRuntimeDeviceTimezone -> deviceTimezone(call, completion)
            NativeMethodChannelHandler.MethodRuntimeResolveLocalDateTime -> resolveLocalDateTime(call, completion)
            NativeMethodChannelHandler.MethodRuntimeLocalizeInstants -> localizeInstants(call, completion)
            else -> completion.notImplemented()
        }
    }

    private fun deviceTimezone(call: MethodCall, completion: SingleCompletion) {
        if (contractProfile != NativeContractProfile.V2) return completion.notImplemented()
        if (!nativeExecutor.validateEmptyRequest(call, completion)) return
        nativeExecutor.executeLocal(call.method, completion) {
            val data = linkedMapOf<String, Any?>("timezone" to deviceTimezoneProvider.currentTimezone())
            RuntimeTimezoneResponseContracts.deviceTimezone(data)
            NativeResultContract.success(data, contractVersion = contractProfile.contractVersion)
        }
    }

    private fun resolveLocalDateTime(call: MethodCall, completion: SingleCompletion) {
        if (contractProfile != NativeContractProfile.V2) return completion.notImplemented()
        val request = nativeExecutor.parse(call, completion) {
            RuntimeTimezoneRequestContracts.resolveLocalDateTime(it)
        } ?: return
        val localDateTime = request.value.getValue("local_datetime") as String
        val timezone = request.value.getValue("timezone") as String
        nativeExecutor.executeNative(
            call.method,
            completion,
            dataValidator = {
                RuntimeTimezoneResponseContracts.resolveLocalDateTime(
                    it,
                    expectedLocalDateTime = localDateTime,
                    expectedTimezone = timezone,
                )
            },
        ) {
            nativeBridge.resolveLocalDateTime(request.toJson())
        }
    }

    private fun localizeInstants(call: MethodCall, completion: SingleCompletion) {
        if (contractProfile != NativeContractProfile.V2) return completion.notImplemented()
        val request = nativeExecutor.parse(call, completion) {
            RuntimeTimezoneRequestContracts.localizeInstants(it)
        } ?: return
        val timezone = request.value.getValue("timezone") as String
        @Suppress("UNCHECKED_CAST")
        val instants = request.value.getValue("instants") as List<String>
        nativeExecutor.executeNative(
            call.method,
            completion,
            dataValidator = {
                RuntimeTimezoneResponseContracts.localizeInstants(
                    it,
                    expectedTimezone = timezone,
                    expectedInstants = instants,
                )
            },
        ) {
            nativeBridge.localizeInstants(request.toJson())
        }
    }
}
