package com.excellentcalendar.excellent_calendar.android.notification

import android.content.Intent
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeContractViolation
import com.excellentcalendar.excellent_calendar.bridge.contract.NotificationTapPayloadContract
import io.flutter.plugin.common.EventChannel
import java.time.Instant

class NotificationTapPayloadStore {
    private var initialPayload: Map<String, Any?>? = null

    @Synchronized
    fun store(payload: Map<String, Any?>) {
        initialPayload = LinkedHashMap(payload)
    }

    @Synchronized
    fun take(): Map<String, Any?>? {
        val payload = initialPayload
        initialPayload = null
        return payload
    }

    @Synchronized
    fun clear() {
        initialPayload = null
    }
}

class NotificationEventHub {
    private var openedSink: EventChannel.EventSink? = null
    private var deliveredSink: EventChannel.EventSink? = null

    val openedStreamHandler = sinkHandler(
        onListen = { openedSink = it },
        onCancel = { openedSink = null },
    )
    val deliveredStreamHandler = sinkHandler(
        onListen = { deliveredSink = it },
        onCancel = { deliveredSink = null },
    )

    @Synchronized
    fun emitOpened(payload: Map<String, Any?>): Boolean {
        val sink = openedSink ?: return false
        sink.success(payload)
        return true
    }

    @Synchronized
    fun emitDelivered(notification: Map<String, Any?>): Boolean {
        val sink = deliveredSink ?: return false
        sink.success(notification)
        return true
    }

    @Synchronized
    fun clear() {
        openedSink = null
        deliveredSink = null
    }

    private fun sinkHandler(
        onListen: (EventChannel.EventSink) -> Unit,
        onCancel: () -> Unit,
    ): EventChannel.StreamHandler {
        return object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) = onListen(events)
            override fun onCancel(arguments: Any?) = onCancel()
        }
    }
}

class NotificationTapCoordinator(
    private val store: NotificationTapPayloadStore,
    private val eventHub: NotificationEventHub,
    private val nowUtc: () -> String = { Instant.now().toString() },
) {
    private val seenNotificationIds = LinkedHashSet<String>()

    @Synchronized
    fun handle(rawPayload: Any?): Boolean {
        val payload = NotificationTapPayloadContract.normalize(rawPayload, nowUtc())
        val notificationId = payload["notification_id"] as String
        if (!seenNotificationIds.add(notificationId)) return false
        while (seenNotificationIds.size > MaxRememberedNotifications) {
            seenNotificationIds.remove(seenNotificationIds.first())
        }
        if (!eventHub.emitOpened(payload)) {
            store.store(payload)
        }
        return true
    }

    fun handleJson(payloadJson: String?): Boolean {
        if (payloadJson.isNullOrBlank()) return false
        return try {
            handle(NativeContractJsonCodec.decodeObject(payloadJson))
        } catch (error: IllegalArgumentException) {
            false
        } catch (error: NativeContractViolation) {
            false
        } catch (error: Exception) {
            false
        }
    }

    companion object {
        private const val MaxRememberedNotifications = 128
    }
}

object AndroidNotificationRuntime {
    val tapPayloadStore = NotificationTapPayloadStore()
    val eventHub = NotificationEventHub()
    val tapCoordinator = NotificationTapCoordinator(tapPayloadStore, eventHub)

    fun handleIntent(intent: Intent?): Boolean {
        if (intent?.action != ActionOpenReminder) return false
        return tapCoordinator.handleJson(intent.getStringExtra(ExtraPayloadJson))
    }

    const val OpenedEventChannel = "excellent_calendar/events/notification_opened"
    const val DeliveredEventChannel = "excellent_calendar/events/notification"
    const val ActionOpenReminder = "excellent_calendar.action.OPEN_REMINDER"
    const val ExtraPayloadJson = "payload_json"
}
