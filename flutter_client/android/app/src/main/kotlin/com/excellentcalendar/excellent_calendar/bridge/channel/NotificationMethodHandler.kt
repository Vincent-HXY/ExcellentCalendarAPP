package com.excellentcalendar.excellent_calendar.bridge.channel

import com.excellentcalendar.excellent_calendar.bridge.contract.OpenNotificationSettingsContract
import com.excellentcalendar.excellent_calendar.bridge.contract.RequestNotificationPermissionContract
import com.excellentcalendar.excellent_calendar.bridge.native.NativeBridgeUnavailableException
import com.excellentcalendar.excellent_calendar.bridge.notification.NotificationMethodOrchestrator
import io.flutter.plugin.common.MethodCall

internal class NotificationMethodHandler(
    private val notificationOrchestrator: NotificationMethodOrchestrator?,
    private val nativeExecutor: NativeCallExecutor,
) : ChannelMethodHandler {
    override val methods = setOf(
        NativeMethodChannelHandler.MethodNotificationInitialize,
        NativeMethodChannelHandler.MethodNotificationPermissionStatus,
        NativeMethodChannelHandler.MethodNotificationRequestPermission,
        NativeMethodChannelHandler.MethodNotificationOpenSettings,
        NativeMethodChannelHandler.MethodNotificationGetInitialTapPayload,
    )

    override fun handle(call: MethodCall, completion: SingleCompletion) {
        when (call.method) {
            NativeMethodChannelHandler.MethodNotificationInitialize -> initialize(call, completion)
            NativeMethodChannelHandler.MethodNotificationPermissionStatus -> permissionStatus(call, completion)
            NativeMethodChannelHandler.MethodNotificationRequestPermission -> requestPermission(call, completion)
            NativeMethodChannelHandler.MethodNotificationOpenSettings -> openSettings(call, completion)
            NativeMethodChannelHandler.MethodNotificationGetInitialTapPayload -> initialTapPayload(call, completion)
            else -> completion.notImplemented()
        }
    }

    private fun initialize(call: MethodCall, completion: SingleCompletion) {
        if (!nativeExecutor.validateEmptyRequest(call, completion)) return
        nativeExecutor.executeLocal(call.method, completion) {
            requireOrchestrator(call.method).initialize()
        }
    }

    private fun permissionStatus(call: MethodCall, completion: SingleCompletion) {
        if (!nativeExecutor.validateEmptyRequest(call, completion)) return
        nativeExecutor.executeLocal(call.method, completion) {
            requireOrchestrator(call.method).permissionStatus()
        }
    }

    private fun requestPermission(call: MethodCall, completion: SingleCompletion) {
        val request = nativeExecutor.parse(
            call,
            completion,
            RequestNotificationPermissionContract::fromMethodArguments,
        ) ?: return
        try {
            requireOrchestrator(call.method).requestPermission(request) { nativeResult ->
                nativeExecutor.complete(call.method, completion, nativeResult)
            }
        } catch (error: Throwable) {
            nativeExecutor.completeInternalFailure(call.method, completion, error)
        }
    }

    private fun openSettings(call: MethodCall, completion: SingleCompletion) {
        val request = nativeExecutor.parse(
            call,
            completion,
            OpenNotificationSettingsContract::fromMethodArguments,
        ) ?: return
        nativeExecutor.executeLocal(call.method, completion) {
            requireOrchestrator(call.method).openSettings(request.settingsTarget)
        }
    }

    private fun initialTapPayload(call: MethodCall, completion: SingleCompletion) {
        if (!nativeExecutor.validateEmptyRequest(call, completion)) return
        nativeExecutor.executeLocal(call.method, completion) {
            requireOrchestrator(call.method).takeInitialTapPayload()
        }
    }

    private fun requireOrchestrator(method: String): NotificationMethodOrchestrator =
        notificationOrchestrator ?: throw NativeBridgeUnavailableException(
            "Notification orchestration is not configured for $method.",
        )
}
