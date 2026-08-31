package com.excellentcalendar.excellent_calendar.bridge.channel

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.excellentcalendar.excellent_calendar.bridge.auth.RefreshTokenSecureStore
import com.excellentcalendar.excellent_calendar.android.appearance.AppearancePreferencesStore
import com.excellentcalendar.excellent_calendar.bridge.native.NativeAnniversaryBridge
import com.excellentcalendar.excellent_calendar.bridge.native.NativeCalendarCoreBridge
import com.excellentcalendar.excellent_calendar.bridge.native.NativeCategoryBridge
import com.excellentcalendar.excellent_calendar.bridge.native.NativeHabitBridge
import com.excellentcalendar.excellent_calendar.bridge.native.NativeContractProfile
import com.excellentcalendar.excellent_calendar.bridge.notification.NotificationMethodOrchestrator
import com.excellentcalendar.excellent_calendar.android.ring.RingRuntime
import com.excellentcalendar.excellent_calendar.bridge.ring.RingMethodOrchestrator
import com.excellentcalendar.excellent_calendar.bridge.reminder.PendingReminderScheduleService
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderNativeOrchestrator
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderScheduleReconciler
import com.excellentcalendar.excellent_calendar.bridge.runtime.AndroidDeviceTimezoneProvider
import com.excellentcalendar.excellent_calendar.bridge.runtime.DeviceTimezoneProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** Dispatches a callback, normally onto Android's main thread. */
fun interface ResultDispatcher {
    fun dispatch(block: () -> Unit)
}

/** Logs normalized bridge lifecycle events without exposing native payloads. */
fun interface NativeBridgeLogger {
    fun log(method: String, requestId: String?, message: String)
}

class MainThreadResultDispatcher : ResultDispatcher {
    private val handler = Handler(Looper.getMainLooper())

    override fun dispatch(block: () -> Unit) {
        handler.post(block)
    }
}

class AndroidNativeBridgeLogger : NativeBridgeLogger {
    override fun log(method: String, requestId: String?, message: String) {
        Log.d(NativeMethodChannelHandler.LogTag, "method=$method request_id=${requestId ?: "null"} $message")
    }
}

/**
 * Flutter MethodChannel entry point.
 *
 * This class owns only the top-level method registry, exactly-once completion lifecycle, and
 * resources shared by the module handlers. Request parsing and platform/native operations are
 * delegated to Runtime/Event/Anniversary/Reminder/Notification handlers.
 */
class NativeMethodChannelHandler(
    private val nativeCalendarCoreBridge: NativeCalendarCoreBridge,
    private val nativeAnniversaryBridge: NativeAnniversaryBridge = nativeCalendarCoreBridge,
    private val nativeCategoryBridge: NativeCategoryBridge = nativeCalendarCoreBridge,
    private val nativeHabitBridge: NativeHabitBridge = nativeCalendarCoreBridge,
    private val reminderOrchestrator: ReminderNativeOrchestrator? = null,
    private val notificationOrchestrator: NotificationMethodOrchestrator? = null,
    private val pendingReminderScheduleService: PendingReminderScheduleService? = null,
    private val reminderScheduleCoordinator: ReminderScheduleReconciler? = null,
    private val ringRuntime: RingRuntime? = null,
    private val ringOrchestrator: RingMethodOrchestrator? = null,
    private val authTokenStore: RefreshTokenSecureStore? = null,
    private val appearanceStore: AppearancePreferencesStore? = null,
    private val contractProfile: NativeContractProfile = NativeContractProfile.V1,
    private val reconcileRetryEnqueuer: (() -> Unit)? = null,
    private val anniversaryCapabilityProvider: AnniversaryCapabilityProvider = AnniversaryCapabilityProvider {
        AnniversaryCapabilitySnapshot(
            notificationPermissionStatus = "unknown",
            exactAlarmPermissionStatus = "unknown",
            canPostNotifications = false,
            canScheduleExactAlarms = false,
        )
    },
    private val executor: Executor = Executors.newSingleThreadExecutor(),
    private val resultDispatcher: ResultDispatcher = MainThreadResultDispatcher(),
    private val logger: NativeBridgeLogger = AndroidNativeBridgeLogger(),
    private val deviceTimezoneProvider: DeviceTimezoneProvider = AndroidDeviceTimezoneProvider,
) : MethodChannel.MethodCallHandler, AutoCloseable {
    private val nativeCallExecutor = NativeCallExecutor(executor, contractProfile, logger)
    private val mutationScheduleHook = MutationScheduleHook(
        reminderScheduleCoordinator,
        reconcileRetryEnqueuer,
        logger,
    )
    private val anniversaryOrchestrator = AnniversaryMethodOrchestrator(
        reminderScheduleCoordinator,
        anniversaryCapabilityProvider,
        reconcileRetryEnqueuer,
        logger,
    )
    private val habitOrchestrator = HabitMutationOrchestrator(
        reminderScheduleCoordinator,
        anniversaryCapabilityProvider,
        reconcileRetryEnqueuer,
        logger,
    )
    private val methodRegistry: Map<String, ChannelMethodHandler> = createMethodRegistry(
        listOf(
            RuntimeMethodHandler(
                nativeCalendarCoreBridge,
                contractProfile,
                nativeCallExecutor,
                deviceTimezoneProvider,
            ),
            EventMethodHandler(
                nativeCalendarCoreBridge,
                contractProfile,
                nativeCallExecutor,
                mutationScheduleHook,
            ),
            CategoryMethodHandler(
                nativeCategoryBridge,
                contractProfile,
                nativeCallExecutor,
            ),
            HabitMethodHandler(
                nativeHabitBridge,
                contractProfile,
                nativeCallExecutor,
                habitOrchestrator,
            ),
            AnniversaryMethodHandler(
                nativeAnniversaryBridge,
                contractProfile,
                nativeCallExecutor,
                anniversaryOrchestrator,
            ),
            ReminderMethodHandler(
                nativeCalendarCoreBridge,
                contractProfile,
                nativeCallExecutor,
                mutationScheduleHook,
                reminderOrchestrator,
                pendingReminderScheduleService,
                reminderScheduleCoordinator,
            ),
            NotificationMethodHandler(notificationOrchestrator, nativeCallExecutor),
            RingMethodHandler(contractProfile, nativeCallExecutor, ringRuntime, ringOrchestrator),
            AuthMethodHandler(
                authTokenStore,
                contractProfile,
                nativeCallExecutor,
            ),
            AppearanceMethodHandler(appearanceStore, nativeCallExecutor),
        ),
    )

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val completion = SingleCompletion(result, resultDispatcher)
        methodRegistry[call.method]?.handle(call, completion) ?: completion.notImplemented()
    }

    override fun close() {
        if (executor is ExecutorService) {
            executor.shutdownNow()
        }
        notificationOrchestrator?.close()
        ringOrchestrator?.close()
    }

    private fun createMethodRegistry(handlers: List<ChannelMethodHandler>): Map<String, ChannelMethodHandler> {
        val registry = linkedMapOf<String, ChannelMethodHandler>()
        handlers.forEach { handler ->
            handler.methods.forEach { method ->
                check(registry.put(method, handler) == null) {
                    "MethodChannel method is registered by multiple handlers: $method"
                }
            }
        }
        return registry
    }

    companion object {
        const val ChannelName = "excellent_calendar/native"
        const val MethodRuntimeDeviceTimezone = "runtime.device_timezone"
        const val MethodRuntimeResolveLocalDateTime = "runtime.resolve_local_datetime"
        const val MethodRuntimeLocalizeInstants = "runtime.localize_instants"
        const val MethodEventCreate = "event.create"
        const val MethodEventUpdate = "event.update"
        const val MethodEventDelete = "event.delete"
        const val MethodEventSearch = "event.search"
        const val MethodEventDetail = "event.detail"
        const val MethodEventComplete = "event.complete"
        const val MethodEventReopen = "event.reopen"
        const val MethodEventListOccurrences = "event.list_occurrences"
        const val MethodEventOccurrenceComplete = "event_occurrence.complete"
        const val MethodEventOccurrenceReopen = "event_occurrence.reopen"
        const val MethodEventOccurrenceSkip = "event_occurrence.skip"
        const val MethodEventOccurrenceCancel = "event_occurrence.cancel"
        const val MethodEventSeriesComplete = "event.complete_series"
        const val MethodEventSeriesReopen = "event.reopen_series"
        const val MethodEventSeriesCancel = "event.cancel_series"
        const val MethodAnniversaryCreate = "anniversary.create"
        const val MethodAnniversaryUpdate = "anniversary.update"
        const val MethodAnniversaryDelete = "anniversary.delete"
        const val MethodAnniversaryDetail = "anniversary.detail"
        const val MethodAnniversaryList = "anniversary.list"
        const val MethodAnniversaryPreviewCountdown = "anniversary.preview_countdown"
        const val MethodAnniversarySetRemindersEnabled = "anniversary.set_reminders_enabled"
        const val MethodAnniversaryListOccurrences = "anniversary.list_occurrences"
        const val MethodCategoryList = "category.list"
        const val MethodCategoryCreate = "category.create"
        const val MethodHabitCreate = "habit.create"
        const val MethodHabitUpdate = "habit.update"
        const val MethodHabitList = "habit.list"
        const val MethodHabitDetail = "habit.detail"
        const val MethodHabitEnd = "habit.end"
        const val MethodHabitDelete = "habit.delete"
        const val MethodHabitCheckIn = "habit.check_in"
        const val MethodHabitClearCheckIn = "habit.clear_check_in"
        const val MethodHabitListDailyStatuses = "habit.list_daily_statuses"
        const val MethodHabitSetReminder = "habit.set_reminder"
        const val MethodAppearanceGetLocal = "appearance.get_local"
        const val MethodAppearanceUpdateLocal = "appearance.update_local"
        const val MethodReminderCreate = "reminder.create"
        const val MethodReminderUpdate = "reminder.update"
        const val MethodReminderCancel = "reminder.cancel"
        const val MethodReminderList = "reminder.list"
        const val MethodReminderSchedulePending = "reminder.schedule_pending"
        const val MethodReminderReconcileSchedule = "reminder.reconcile_schedule"
        const val MethodNotificationInitialize = "notification.initialize"
        const val MethodNotificationPermissionStatus = "notification.permission_status"
        const val MethodNotificationRequestPermission = "notification.request_permission"
        const val MethodNotificationOpenSettings = "notification.open_settings"
        const val MethodNotificationGetInitialTapPayload = "notification.get_initial_tap_payload"
        const val MethodRingGetState = "ring.get_state"
        const val MethodRingPickRingtone = "ring.pick_ringtone"
        const val MethodRingUpdateSettings = "ring.update_settings"
        const val MethodRingTest = "ring.test"
        const val MethodRingStopActive = "ring.stop_active"
        const val MethodRingSnoozeActive = "ring.snooze_active"
        const val MethodRingCompleteItem = "ring.complete_item"
        const val MethodAuthRefreshTokenStore = "auth.refresh_token.store"
        const val MethodAuthRefreshTokenRead = "auth.refresh_token.read"
        const val MethodAuthRefreshTokenDelete = "auth.refresh_token.delete"
        const val MethodAuthRefreshTokenExists = "auth.refresh_token.exists"
        const val LogTag = "ExcellentCalendarNative"
    }
}
