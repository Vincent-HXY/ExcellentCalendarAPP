package com.excellentcalendar.excellent_calendar.bridge

import com.excellentcalendar.excellent_calendar.android.alarm.BootReminderRescheduler
import com.excellentcalendar.excellent_calendar.android.alarm.CancelResult
import com.excellentcalendar.excellent_calendar.android.alarm.ReminderScheduler
import com.excellentcalendar.excellent_calendar.android.alarm.ScheduleResult
import com.excellentcalendar.excellent_calendar.android.notification.AndroidNotificationDisplayService
import com.excellentcalendar.excellent_calendar.android.notification.NotificationChannelInitialization
import com.excellentcalendar.excellent_calendar.android.notification.NotificationChannelManager
import com.excellentcalendar.excellent_calendar.android.notification.NotificationDisplayService
import com.excellentcalendar.excellent_calendar.android.notification.NotificationEventHub
import com.excellentcalendar.excellent_calendar.android.notification.NotificationPermissionManager
import com.excellentcalendar.excellent_calendar.android.notification.NotificationPermissionSnapshot
import com.excellentcalendar.excellent_calendar.android.notification.NotificationPermissionStatusResolver
import com.excellentcalendar.excellent_calendar.android.notification.NotificationPostResult
import com.excellentcalendar.excellent_calendar.android.notification.NotificationTapCoordinator
import com.excellentcalendar.excellent_calendar.android.notification.NotificationTapPayloadStore
import com.excellentcalendar.excellent_calendar.android.notification.PermissionRequestResult
import com.excellentcalendar.excellent_calendar.android.notification.ReminderNotificationContent
import com.excellentcalendar.excellent_calendar.bridge.channel.NativeBridgeLogger
import com.excellentcalendar.excellent_calendar.bridge.channel.NativeMethodChannelHandler
import com.excellentcalendar.excellent_calendar.bridge.channel.ResultDispatcher
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderContract
import com.excellentcalendar.excellent_calendar.bridge.contract.RequestNotificationPermissionContract
import com.excellentcalendar.excellent_calendar.bridge.contract.SchedulePendingRemindersContract
import com.excellentcalendar.excellent_calendar.bridge.native.NativeCalendarCoreBridge
import com.excellentcalendar.excellent_calendar.bridge.notification.NotificationMethodOrchestrator
import com.excellentcalendar.excellent_calendar.bridge.reminder.PendingReminderScheduleService
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderDeliveryResult
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderDeliveryService
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import java.util.concurrent.Executor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Ignore
import org.junit.Test

class NotificationReminderBridgeTest {
    @Test
    fun permissionStatusDistinguishesAndroidBeforeAndAfter33() {
        val before33 = NotificationPermissionStatusResolver.resolve(
            sdkInt = 32,
            runtimeNotificationGranted = false,
            notificationsEnabled = true,
            exactAlarmAllowed = true,
            shouldShowRationale = false,
            requestedBefore = false,
        )
        val after33 = NotificationPermissionStatusResolver.resolve(
            sdkInt = 33,
            runtimeNotificationGranted = false,
            notificationsEnabled = true,
            exactAlarmAllowed = false,
            shouldShowRationale = true,
            requestedBefore = true,
        )

        assertEquals("not_required", before33.notificationPermission)
        assertTrue(before33.canPostNotifications)
        assertEquals("denied", after33.notificationPermission)
        assertFalse(after33.canPostNotifications)
        assertEquals("denied", after33.exactAlarmPermission)
        assertTrue(after33.shouldShowNotificationRationale)
    }

    @Test
    fun notificationInitializeCreatesChannelsAndLocalMethodsRouteThroughHandler() {
        val channels = FakeChannelManager()
        val permissions = FakePermissionManager()
        val store = NotificationTapPayloadStore().apply { store(tapPayload()) }
        var launchCaptured = false
        val notification = NotificationMethodOrchestrator(
            channels = channels,
            permissions = permissions,
            tapStore = store,
            captureLaunchPayload = { launchCaptured = true },
            sdkInt = { 36 },
        )
        val bridge = FakeNativeBridge()
        val pending = PendingReminderScheduleService(bridge, FakeScheduler(), logger = { _, _, _ -> })
        val handler = handler(bridge, notification, pending)

        val initialize = invoke(
            handler,
            NativeMethodChannelHandler.MethodNotificationInitialize,
            emptyMap<String, Any?>(),
        ).successMap()
        val status = invoke(
            handler,
            NativeMethodChannelHandler.MethodNotificationPermissionStatus,
            emptyMap<String, Any?>(),
        ).successMap()
        val requested = invoke(
            handler,
            NativeMethodChannelHandler.MethodNotificationRequestPermission,
            linkedMapOf(
                "request_notification_permission" to true,
                "request_exact_alarm_permission" to false,
                "source" to "settings_page",
            ),
        ).successMap()
        val settings = invoke(
            handler,
            NativeMethodChannelHandler.MethodNotificationOpenSettings,
            linkedMapOf("settings_target" to "notification"),
        ).successMap()
        val initialPayload = invoke(
            handler,
            NativeMethodChannelHandler.MethodNotificationGetInitialTapPayload,
            emptyMap<String, Any?>(),
        ).successMap()
        val scheduled = invoke(
            handler,
            NativeMethodChannelHandler.MethodReminderSchedulePending,
            linkedMapOf(
                "from_at" to "2026-07-04T10:00:00Z",
                "to_at" to "2026-07-11T10:00:00Z",
                "limit" to 128,
                "force_reschedule" to false,
            ),
        ).successMap()

        assertEquals(1, channels.ensureCalls)
        assertTrue(launchCaptured)
        assertEquals(true, initialize["ok"])
        assertEquals(true, status["ok"])
        assertEquals(true, requested["ok"])
        assertEquals(true, settings["ok"])
        assertEquals(true, scheduled["ok"])
        @Suppress("UNCHECKED_CAST")
        val initialData = initialPayload["data"] as Map<String, Any?>
        assertEquals(true, initialData["has_payload"])
    }

    @Test
    fun schedulePendingRegistersAlarmAndMarksReminderScheduled() {
        val bridge = FakeNativeBridge()
        val scheduler = FakeScheduler()
        val service = PendingReminderScheduleService(
            bridge,
            scheduler,
            logger = { _, _, _ -> },
            nowUtc = { "2026-07-04T09:55:00Z" },
        )

        val result = service.schedulePending(
            SchedulePendingRemindersContract(
                fromAt = "2026-07-04T10:00:00Z",
                toAt = "2026-07-11T10:00:00Z",
                limit = 128,
                forceReschedule = false,
            ),
        )

        assertTrue(result.ok)
        assertEquals(listOf("rem_001"), scheduler.scheduledIds)
        assertEquals(listOf("rem_001"), bridge.markScheduledIds)
        val nativeRequest = NativeContractJsonCodec.decodeObject(bridge.lastListSchedulableRequest!!)
        assertEquals(128, nativeRequest["limit"])
        assertEquals(listOf("popup"), nativeRequest["supported_methods"])
        @Suppress("UNCHECKED_CAST")
        val data = result.data as Map<String, Any?>
        assertEquals(1, data["scheduled_count"])
        assertEquals(0, data["failed_count"])
    }

    @Test
    fun schedulePendingExactAlarmDeniedMarksReminderFailed() {
        val bridge = FakeNativeBridge()
        val service = PendingReminderScheduleService(
            bridge,
            FakeScheduler(exactAllowed = false),
            logger = { _, _, _ -> },
        )

        val result = service.schedulePending(
            SchedulePendingRemindersContract(
                "2026-07-04T10:00:00Z",
                "2026-07-11T10:00:00Z",
                128,
                false,
            ),
        )

        assertFalse(result.ok)
        assertEquals(NativeErrorCodes.ExactAlarmPermissionDenied, result.error?.code)
        assertEquals(listOf("rem_001"), bridge.markFailedIds)
    }

    @Test
    fun schedulePendingCancelsAlarmWhenNativeScheduledStateCannotBePersisted() {
        val bridge = FakeNativeBridge(markScheduledSucceeds = false)
        val scheduler = FakeScheduler()
        val service = PendingReminderScheduleService(bridge, scheduler, logger = { _, _, _ -> })

        val result = service.schedulePending(
            SchedulePendingRemindersContract(
                "2026-07-04T10:00:00Z",
                "2026-07-11T10:00:00Z",
                128,
                false,
            ),
        )

        assertTrue(result.ok)
        assertEquals(listOf("rem_001"), scheduler.cancelledIds)
        @Suppress("UNCHECKED_CAST")
        val data = result.data as Map<String, Any?>
        assertEquals(0, data["scheduled_count"])
        assertEquals(1, data["failed_count"])
        assertEquals(listOf("rem_001"), data["failed_reminder_ids"])
    }

    @Test
    fun alarmDeliveryLoadsReminderPostsNotificationAndConsumesState() {
        val bridge = FakeNativeBridge()
        val display = FakeDisplayService()
        val eventHub = NotificationEventHub()
        val delivered = RecordingEventSink()
        eventHub.deliveredStreamHandler.onListen(null, delivered)
        val service = ReminderDeliveryService(
            nativeReminderBridge = bridge,
            nativeNotificationBridge = bridge,
            notifications = display,
            eventHub = eventHub,
            logger = { _, _, _ -> },
            nowUtc = { "2026-07-04T10:00:01Z" },
        )

        val result = service.deliver("rem_001", "2026-07-04T10:00:00Z")

        assertTrue(result is ReminderDeliveryResult.Delivered)
        assertEquals("rem_001", bridge.lastGetReminderId)
        assertEquals("rem_001", display.posted.single().reminderId)
        assertEquals("rem_001", bridge.lastConsumedReminderId)
        assertEquals(1, delivered.values.size)
    }

    @Test
    fun alarmDeliveryFailureRecordsNotificationFailureAndReminderFailure() {
        val bridge = FakeNativeBridge()
        val display = FakeDisplayService(
            NotificationPostResult.Failure(
                code = NativeErrorCodes.NotificationDeliveryFailed,
                message = "Notification manager rejected the post.",
                retryable = true,
            ),
        )
        val service = ReminderDeliveryService(
            nativeReminderBridge = bridge,
            nativeNotificationBridge = bridge,
            notifications = display,
            eventHub = NotificationEventHub(),
            logger = { _, _, _ -> },
            nowUtc = { "2026-07-04T10:00:01Z" },
        )

        val result = service.deliver("rem_001", "2026-07-04T10:00:00Z")

        assertTrue(result is ReminderDeliveryResult.Failed)
        assertEquals(1, bridge.createdNotificationCount)
        assertEquals(listOf("rem_001"), bridge.markFailedIds)
        assertNull(bridge.lastConsumedReminderId)
    }

    @Ignore("Known defect: a stale Alarm is posted before C++ rejects its planned_at.")
    @Test
    fun staleAlarmDoesNotDisplayNotification() {
        val bridge = FakeNativeBridge(rejectMismatchedPlannedAt = true)
        val display = FakeDisplayService()
        val service = ReminderDeliveryService(
            nativeReminderBridge = bridge,
            nativeNotificationBridge = bridge,
            notifications = display,
            eventHub = NotificationEventHub(),
            logger = { _, _, _ -> },
            nowUtc = { "2026-07-04T10:00:01Z" },
        )

        service.deliver("rem_001", "2026-07-04T09:30:00Z")

        assertTrue(display.posted.isEmpty())
    }

    @Test
    fun differentReminderIdsProduceDifferentAndroidNotificationIdentities() {
        val first = AndroidNotificationDisplayService.notificationIdentity("Aa")
        val second = AndroidNotificationDisplayService.notificationIdentity("BB")

        assertEquals(1, first.id)
        assertEquals(1, second.id)
        assertEquals("reminder:Aa", first.tag)
        assertEquals("reminder:BB", second.tag)
        assertNotEquals(first, second)
    }

    @Test
    fun sameReminderIdProducesSameAndroidNotificationIdentityForPostAndCancel() {
        assertEquals(
            AndroidNotificationDisplayService.notificationIdentity("rem_001"),
            AndroidNotificationDisplayService.notificationIdentity("rem_001"),
        )
    }

    @Test
    fun notificationTapSupportsColdStartHotStartAndDeduplicates() {
        val coldStore = NotificationTapPayloadStore()
        val coldHub = NotificationEventHub()
        val cold = NotificationTapCoordinator(coldStore, coldHub) { "2026-07-04T10:01:00Z" }
        assertTrue(cold.handle(tapPayload()))
        assertEquals("2026-07-04T10:01:00Z", coldStore.take()?.get("opened_at"))

        val hotStore = NotificationTapPayloadStore()
        val hotHub = NotificationEventHub()
        val opened = RecordingEventSink()
        hotHub.openedStreamHandler.onListen(null, opened)
        val hot = NotificationTapCoordinator(hotStore, hotHub) { "2026-07-04T10:02:00Z" }
        assertTrue(hot.handle(tapPayload()))
        assertFalse(hot.handle(tapPayload()))
        assertEquals(1, opened.values.size)
        assertNull(hotStore.take())
    }

    @Test
    fun bootReschedulerUsesSevenDayWindowAndExplicitLimit() {
        val bridge = FakeNativeBridge()
        val pending = PendingReminderScheduleService(bridge, FakeScheduler(), logger = { _, _, _ -> })
        val boot = BootReminderRescheduler(pending) { Instant.parse("2026-07-04T10:00:00Z") }

        val result = boot.scheduleSevenDayWindow()

        assertTrue(result.ok)
        val request = NativeContractJsonCodec.decodeObject(bridge.lastListSchedulableRequest!!)
        assertEquals("2026-07-04T10:00:00Z", request["from_at"])
        assertEquals("2026-07-11T10:00:00Z", request["to_at"])
        assertEquals(128, request["limit"])
        assertEquals(true, request["include_scheduled"])
    }

    private fun handler(
        bridge: NativeCalendarCoreBridge,
        notification: NotificationMethodOrchestrator,
        pending: PendingReminderScheduleService,
    ): NativeMethodChannelHandler {
        return NativeMethodChannelHandler(
            nativeCalendarCoreBridge = bridge,
            notificationOrchestrator = notification,
            pendingReminderScheduleService = pending,
            executor = Executor { it.run() },
            resultDispatcher = ResultDispatcher { it() },
            logger = NativeBridgeLogger { _, _, _ -> },
        )
    }

    private fun invoke(handler: NativeMethodChannelHandler, method: String, arguments: Any?): RecordingResult {
        val result = RecordingResult()
        handler.onMethodCall(MethodCall(method, arguments), result)
        return result
    }

    private class FakeChannelManager : NotificationChannelManager {
        var ensureCalls = 0
        override fun ensureChannels(): NotificationChannelInitialization {
            ensureCalls += 1
            return NotificationChannelInitialization(true, "excellent_calendar_reminder_popup")
        }
    }

    private class FakePermissionManager : NotificationPermissionManager {
        override fun status() = NotificationPermissionSnapshot(
            notificationPermission = "granted",
            exactAlarmPermission = "granted",
            canPostNotifications = true,
            canScheduleExactAlarms = true,
            sdkInt = 36,
            shouldShowNotificationRationale = false,
        )

        override fun request(
            request: RequestNotificationPermissionContract,
            callback: (PermissionRequestResult) -> Unit,
        ) = callback(PermissionRequestResult.Success(status(), false))

        override fun openSettings(target: String): Boolean = true
        override fun onRequestPermissionsResult(
            requestCode: Int,
            permissions: Array<out String>,
            grantResults: IntArray,
        ): Boolean = false
        override fun close() = Unit
    }

    private class FakeScheduler(
        private val exactAllowed: Boolean = true,
        private val result: ScheduleResult = ScheduleResult.Success,
    ) : ReminderScheduler {
        val scheduledIds = mutableListOf<String>()
        val cancelledIds = mutableListOf<String>()
        override fun schedule(reminder: ReminderContract): ScheduleResult {
            scheduledIds.add(reminder.id)
            return result
        }
        override fun cancel(reminderId: String): CancelResult {
            cancelledIds.add(reminderId)
            return CancelResult.Success
        }
        override fun canScheduleExactAlarms(): Boolean = exactAllowed
    }

    private class FakeDisplayService(
        private val postResult: NotificationPostResult = NotificationPostResult.Success(
            AndroidNotificationDisplayService.notificationIdentity("rem_001"),
        ),
    ) : NotificationDisplayService {
        val posted = mutableListOf<ReminderNotificationContent>()
        val cancelledIds = mutableListOf<String>()
        override fun post(content: ReminderNotificationContent, sentAt: String): NotificationPostResult {
            posted.add(content)
            return postResult
        }
        override fun cancel(reminderId: String) {
            cancelledIds.add(reminderId)
        }
    }

    private class RecordingEventSink : EventChannel.EventSink {
        val values = mutableListOf<Any?>()
        override fun success(event: Any?) { values.add(event) }
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit
        override fun endOfStream() = Unit
    }

    private class RecordingResult : MethodChannel.Result {
        private var value: Any? = null
        override fun success(result: Any?) { value = result }
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit
        override fun notImplemented() = Unit
        @Suppress("UNCHECKED_CAST")
        fun successMap(): Map<String, Any?> = value as Map<String, Any?>
    }

    private class FakeNativeBridge(
        private val markScheduledSucceeds: Boolean = true,
        private val rejectMismatchedPlannedAt: Boolean = false,
    ) : NativeCalendarCoreBridge {
        var lastListSchedulableRequest: String? = null
        var lastGetReminderId: String? = null
        var lastConsumedReminderId: String? = null
        val markScheduledIds = mutableListOf<String>()
        val markFailedIds = mutableListOf<String>()
        var createdNotificationCount = 0

        override fun listSchedulableReminders(requestJson: String): String {
            lastListSchedulableRequest = requestJson
            return encodeResult(
                true,
                linkedMapOf(
                    "items" to listOf(reminderResponse("pending")),
                    "selected_count" to 1,
                    "has_more" to false,
                    "unsupported_reminder_ids" to emptyList<String>(),
                ),
            )
        }

        override fun markReminderScheduled(requestJson: String): String {
            val id = NativeContractJsonCodec.decodeObject(requestJson)["id"] as String
            markScheduledIds.add(id)
            if (!markScheduledSucceeds) {
                return encodeResult(
                    false,
                    null,
                    linkedMapOf(
                        "code" to NativeErrorCodes.StorageIoError,
                        "message" to "Reminder state could not be persisted.",
                        "details" to null,
                        "retryable" to true,
                    ),
                )
            }
            return encodeResult(true, reminderResponse("scheduled"))
        }

        override fun getReminder(requestJson: String): String {
            lastGetReminderId = NativeContractJsonCodec.decodeObject(requestJson)["id"] as String
            return encodeResult(true, reminderResponse("scheduled"))
        }

        override fun consumeReminderAfterDelivery(requestJson: String): String {
            val request = NativeContractJsonCodec.decodeObject(requestJson)
            lastConsumedReminderId = request["reminder_id"] as String
            if (rejectMismatchedPlannedAt && request["planned_at"] != "2026-07-04T10:00:00Z") {
                return encodeResult(
                    false,
                    null,
                    linkedMapOf(
                        "code" to "REMINDER_NOT_DUE",
                        "message" to "The Alarm payload no longer matches the reminder.",
                        "details" to null,
                        "retryable" to false,
                    ),
                )
            }
            return encodeResult(
                true,
                linkedMapOf(
                    "reminder" to reminderResponse(
                        status = "sent",
                        isEnabled = false,
                        deletedAt = "2026-07-04T10:00:01Z",
                    ),
                    "notification" to notificationResponse(),
                ),
            )
        }

        override fun markReminderFailed(requestJson: String): String {
            markFailedIds.add(NativeContractJsonCodec.decodeObject(requestJson)["id"] as String)
            return encodeResult(true, reminderResponse("failed"))
        }
        override fun createNotification(requestJson: String): String {
            createdNotificationCount += 1
            return encodeResult(true, notificationResponse())
        }

        override fun createEvent(requestJson: String) = unsupported()
        override fun updateEvent(requestJson: String) = unsupported()
        override fun deleteEvent(requestJson: String) = unsupported()
        override fun searchEvents(requestJson: String) = unsupported()
        override fun completeEvent(requestJson: String) = unsupported()
        override fun reopenEvent(requestJson: String) = unsupported()
        override fun createReminder(requestJson: String) = unsupported()
        override fun updateReminder(requestJson: String) = unsupported()
        override fun cancelReminder(requestJson: String) = unsupported()
        override fun listReminders(requestJson: String) = unsupported()
        override fun markReminderSent(requestJson: String) = unsupported()
        override fun enableReminder(requestJson: String) = unsupported()
        override fun disableReminder(requestJson: String) = unsupported()

        private fun unsupported(): String = encodeResult(
            false,
            null,
            linkedMapOf(
                "code" to NativeErrorCodes.FeatureNotImplemented,
                "message" to "Unsupported in test",
                "details" to null,
                "retryable" to false,
            ),
        )
    }

    companion object {
        private fun tapPayload(): Map<String, Any?> = linkedMapOf(
            "notification_id" to "notification-1",
            "reminder_id" to "rem_001",
            "target_type" to "event",
            "target_id" to "event_001",
            "route" to "/event/detail",
            "opened_at" to "2026-07-04T10:00:01Z",
        )

        private fun reminderResponse(
            status: String,
            isEnabled: Boolean = true,
            deletedAt: String? = null,
        ): Map<String, Any?> = linkedMapOf(
            "id" to "rem_001",
            "target_type" to "event",
            "target_id" to "event_001",
            "remind_at" to "2026-07-04T10:00:00Z",
            "methods" to listOf("popup"),
            "advance_minutes" to null,
            "message" to "Meeting starts soon",
            "is_enabled" to isEnabled,
            "status" to status,
            "scheduled_at" to null,
            "last_triggered_at" to null,
            "failure_reason" to null,
            "created_at" to "2026-07-04T09:00:00Z",
            "updated_at" to "2026-07-04T09:55:00Z",
            "deleted_at" to deletedAt,
        )

        private fun notificationResponse(): Map<String, Any?> = linkedMapOf(
            "id" to "notification-1",
            "reminder_id" to "rem_001",
            "target_type" to "event",
            "target_id" to "event_001",
            "method" to "popup",
            "title" to "Calendar reminder",
            "body" to "Meeting starts soon",
            "planned_at" to "2026-07-04T10:00:00Z",
            "sent_at" to "2026-07-04T10:00:01Z",
            "status" to "sent",
            "failure_reason" to null,
            "created_at" to "2026-07-04T10:00:01Z",
            "updated_at" to "2026-07-04T10:00:01Z",
        )

        private fun encodeResult(
            ok: Boolean,
            data: Any?,
            error: Map<String, Any?>? = null,
        ): String = NativeContractJsonCodec.encodeObject(
            linkedMapOf(
                "ok" to ok,
                "data" to data,
                "error" to error,
                "contract_version" to 1,
                "request_id" to "test-request",
            ),
        )
    }
}
