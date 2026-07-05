package com.excellentcalendar.excellent_calendar.android.notification

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.RequestNotificationPermissionContract

data class NotificationPermissionSnapshot(
    val notificationPermission: String,
    val exactAlarmPermission: String,
    val canPostNotifications: Boolean,
    val canScheduleExactAlarms: Boolean,
    val sdkInt: Int,
    val shouldShowNotificationRationale: Boolean,
) {
    fun statusMap(): Map<String, Any?> = linkedMapOf(
        "notification_permission" to notificationPermission,
        "exact_alarm_permission" to exactAlarmPermission,
        "can_post_notifications" to canPostNotifications,
        "can_schedule_exact_alarms" to canScheduleExactAlarms,
        "sdk_int" to sdkInt,
        "should_show_notification_rationale" to shouldShowNotificationRationale,
    )

    fun requestMap(shouldOpenSettings: Boolean, message: String? = null): Map<String, Any?> = linkedMapOf(
        "notification_permission" to notificationPermission,
        "exact_alarm_permission" to exactAlarmPermission,
        "can_post_notifications" to canPostNotifications,
        "can_schedule_exact_alarms" to canScheduleExactAlarms,
        "should_open_settings" to shouldOpenSettings,
        "message" to message,
    )
}

sealed class PermissionRequestResult {
    data class Success(
        val snapshot: NotificationPermissionSnapshot,
        val shouldOpenSettings: Boolean,
        val message: String? = null,
    ) : PermissionRequestResult()

    data class Failure(
        val code: String,
        val message: String,
        val retryable: Boolean,
    ) : PermissionRequestResult()
}

interface NotificationPermissionManager {
    fun status(): NotificationPermissionSnapshot
    fun request(
        request: RequestNotificationPermissionContract,
        callback: (PermissionRequestResult) -> Unit,
    )
    fun openSettings(target: String): Boolean
    fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean
    fun close()
}

object NotificationPermissionStatusResolver {
    fun resolve(
        sdkInt: Int,
        runtimeNotificationGranted: Boolean,
        notificationsEnabled: Boolean,
        exactAlarmAllowed: Boolean,
        shouldShowRationale: Boolean,
        requestedBefore: Boolean,
    ): NotificationPermissionSnapshot {
        val notificationStatus = if (sdkInt < 33) {
            "not_required"
        } else if (runtimeNotificationGranted) {
            "granted"
        } else if (requestedBefore && !shouldShowRationale) {
            "permanently_denied"
        } else {
            "denied"
        }
        val exactStatus = if (sdkInt < 31) {
            "not_required"
        } else if (exactAlarmAllowed) {
            "granted"
        } else {
            "denied"
        }
        return NotificationPermissionSnapshot(
            notificationPermission = notificationStatus,
            exactAlarmPermission = exactStatus,
            canPostNotifications = notificationsEnabled && (sdkInt < 33 || runtimeNotificationGranted),
            canScheduleExactAlarms = sdkInt < 31 || exactAlarmAllowed,
            sdkInt = sdkInt,
            shouldShowNotificationRationale = sdkInt >= 33 && shouldShowRationale,
        )
    }
}

class AndroidNotificationPermissionManager(
    private val activity: Activity,
) : NotificationPermissionManager {
    private val preferences = activity.getSharedPreferences(PreferencesName, Activity.MODE_PRIVATE)
    private var pending: PendingRequest? = null

    override fun status(): NotificationPermissionSnapshot {
        val sdk = Build.VERSION.SDK_INT
        val runtimeGranted = sdk < 33 || activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        val notificationsEnabled = if (sdk >= Build.VERSION_CODES.N) {
            activity.getSystemService(NotificationManager::class.java).areNotificationsEnabled()
        } else {
            true
        }
        val exactAllowed = if (sdk >= Build.VERSION_CODES.S) {
            activity.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()
        } else {
            true
        }
        val rationale = sdk >= 33 && activity.shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)
        return NotificationPermissionStatusResolver.resolve(
            sdkInt = sdk,
            runtimeNotificationGranted = runtimeGranted,
            notificationsEnabled = notificationsEnabled,
            exactAlarmAllowed = exactAllowed,
            shouldShowRationale = rationale,
            requestedBefore = preferences.getBoolean(KeyNotificationRequested, false),
        )
    }

    override fun request(
        request: RequestNotificationPermissionContract,
        callback: (PermissionRequestResult) -> Unit,
    ) {
        if (pending != null) {
            callback(
                PermissionRequestResult.Failure(
                    NativeErrorCodes.NativeInternalError,
                    "A notification permission request is already active.",
                    retryable = true,
                ),
            )
            return
        }
        val needsNotificationDialog = request.requestNotificationPermission &&
            Build.VERSION.SDK_INT >= 33 &&
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        if (needsNotificationDialog) {
            preferences.edit().putBoolean(KeyNotificationRequested, true).apply()
            pending = PendingRequest(request.requestExactAlarmPermission, callback)
            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NotificationRequestCode)
            return
        }
        finishRequest(request.requestExactAlarmPermission, callback)
    }

    override fun openSettings(target: String): Boolean {
        val intent = when (target) {
            "notification" -> Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
            "exact_alarm" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                    .setData(Uri.parse("package:${activity.packageName}"))
            } else {
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(Uri.parse("package:${activity.packageName}"))
            }
            "application" -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:${activity.packageName}"))
            else -> return false
        }
        return try {
            activity.startActivity(intent)
            true
        } catch (error: RuntimeException) {
            false
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != NotificationRequestCode) return false
        val active = pending ?: return true
        pending = null
        finishRequest(active.requestExactAlarm, active.callback)
        return true
    }

    override fun close() {
        pending?.callback?.invoke(
            PermissionRequestResult.Failure(
                NativeErrorCodes.NativeInternalError,
                "Notification permission request was interrupted.",
                retryable = true,
            ),
        )
        pending = null
    }

    private fun finishRequest(
        requestExactAlarm: Boolean,
        callback: (PermissionRequestResult) -> Unit,
    ) {
        val beforeSettings = status()
        val shouldOpen = requestExactAlarm && !beforeSettings.canScheduleExactAlarms
        val opened = if (shouldOpen) openSettings("exact_alarm") else false
        if (shouldOpen && !opened) {
            callback(
                PermissionRequestResult.Failure(
                    NativeErrorCodes.PermissionDenied,
                    "Android exact alarm settings could not be opened.",
                    retryable = true,
                ),
            )
            return
        }
        callback(
            PermissionRequestResult.Success(
                snapshot = status(),
                shouldOpenSettings = shouldOpen,
                message = if (shouldOpen) "Exact alarm access must be granted in Android settings." else null,
            ),
        )
    }

    private data class PendingRequest(
        val requestExactAlarm: Boolean,
        val callback: (PermissionRequestResult) -> Unit,
    )

    companion object {
        const val NotificationRequestCode = 9201
        private const val PreferencesName = "excellent_calendar_notification_permissions"
        private const val KeyNotificationRequested = "post_notifications_requested"
    }
}
