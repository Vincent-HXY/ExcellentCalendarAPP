package com.excellentcalendar.excellent_calendar.bridge.notification

import android.os.Build
import com.excellentcalendar.excellent_calendar.android.notification.NotificationChannelManager
import com.excellentcalendar.excellent_calendar.android.notification.NotificationPermissionManager
import com.excellentcalendar.excellent_calendar.android.notification.NotificationTapPayloadStore
import com.excellentcalendar.excellent_calendar.android.notification.PermissionRequestResult
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.RequestNotificationPermissionContract

class NotificationMethodOrchestrator(
    private val channels: NotificationChannelManager,
    private val permissions: NotificationPermissionManager,
    private val tapStore: NotificationTapPayloadStore,
    private val captureLaunchPayload: () -> Unit,
    private val sdkInt: () -> Int = { Build.VERSION.SDK_INT },
) {
    fun initialize(): NativeResultContract {
        return try {
            val initialized = channels.ensureChannels()
            captureLaunchPayload()
            NativeResultContract.success(
                linkedMapOf(
                    "initialized" to true,
                    "notification_channel_ready" to initialized.ready,
                    "default_channel_id" to initialized.defaultChannelId,
                    "sdk_int" to sdkInt(),
                    "message" to null,
                ),
            )
        } catch (error: Throwable) {
            NativeResultContract.failure(
                code = NativeErrorCodes.NotificationInitializationFailed,
                message = "Android notification system initialization failed.",
                details = linkedMapOf("reason" to error.javaClass.simpleName),
                retryable = true,
            )
        }
    }

    fun permissionStatus(): NativeResultContract {
        return NativeResultContract.success(permissions.status().statusMap())
    }

    fun requestPermission(
        request: RequestNotificationPermissionContract,
        callback: (NativeResultContract) -> Unit,
    ) {
        permissions.request(request) { result ->
            callback(
                when (result) {
                    is PermissionRequestResult.Success -> NativeResultContract.success(
                        result.snapshot.requestMap(result.shouldOpenSettings, result.message),
                    )
                    is PermissionRequestResult.Failure -> NativeResultContract.failure(
                        code = result.code,
                        message = result.message,
                        retryable = result.retryable,
                    )
                },
            )
        }
    }

    fun openSettings(target: String): NativeResultContract {
        val opened = permissions.openSettings(target)
        return if (opened) {
            NativeResultContract.success(
                linkedMapOf("performed" to true, "message" to null),
            )
        } else {
            NativeResultContract.failure(
                code = NativeErrorCodes.PermissionDenied,
                message = "Android settings page could not be opened.",
                details = linkedMapOf("settings_target" to target),
                retryable = true,
            )
        }
    }

    fun takeInitialTapPayload(): NativeResultContract {
        val payload = tapStore.take()
        return NativeResultContract.success(
            linkedMapOf(
                "has_payload" to (payload != null),
                "payload" to payload,
            ),
        )
    }

    fun close() {
        permissions.close()
    }
}
