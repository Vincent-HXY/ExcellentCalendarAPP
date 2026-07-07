package com.excellentcalendar.excellent_calendar.bridge

import com.excellentcalendar.excellent_calendar.android.alarm.CancelResult
import com.excellentcalendar.excellent_calendar.android.alarm.DispatchAlarmScheduler
import com.excellentcalendar.excellent_calendar.android.alarm.ScheduleResult
import com.excellentcalendar.excellent_calendar.android.notification.NotificationDisplayService
import com.excellentcalendar.excellent_calendar.android.notification.NotificationEventHub
import com.excellentcalendar.excellent_calendar.android.notification.NotificationPostResult
import com.excellentcalendar.excellent_calendar.android.notification.ReminderNotificationContent
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReconcileReminderScheduleContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderScheduleTrigger
import com.excellentcalendar.excellent_calendar.bridge.native.NativeEventBridge
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderDeliveryService
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderScheduleCoordinator
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class ReminderScheduleCoordinatorTest {
    @Test
    fun `reconcile registers only the queue head and marks its timestamp scheduled`() {
        val bridge = QueueBridge(hasHead = true)
        val scheduler = FakeDispatchScheduler()
        val coordinator = coordinator(bridge, scheduler)

        val result = coordinator.reconcile(
            ReconcileReminderScheduleContract(ReminderScheduleTrigger.AppStart, force = false),
        )

        assertTrue(result.ok)
        assertEquals(listOf(FutureAt), scheduler.scheduledAt)
        assertEquals(listOf("future-1"), bridge.markedScheduled)
        @Suppress("UNCHECKED_CAST")
        assertEquals(FutureAt, (result.data as Map<String, Any?>)["next_remind_at"])
    }

    @Test
    fun `reconcile cancels dispatcher when durable queue is empty`() {
        val scheduler = FakeDispatchScheduler()
        val result = coordinator(QueueBridge(hasHead = false), scheduler).reconcile(
            ReconcileReminderScheduleContract(ReminderScheduleTrigger.PeriodicWorker, force = true),
        )

        assertTrue(result.ok)
        assertEquals(1, scheduler.cancelCount)
        assertTrue(scheduler.scheduledAt.isEmpty())
    }

    @Test
    fun `permission denial leaves queue durable and reports retryable failure`() {
        val bridge = QueueBridge(hasHead = true)
        val scheduler = FakeDispatchScheduler(
            scheduleResult = ScheduleResult.Failure(
                "EXACT_ALARM_PERMISSION_DENIED",
                "permission denied",
                retryable = true,
            ),
        )
        val result = coordinator(bridge, scheduler).reconcile(
            ReconcileReminderScheduleContract(ReminderScheduleTrigger.AppResume, force = true),
        )

        assertFalse(result.ok)
        assertEquals("EXACT_ALARM_PERMISSION_DENIED", result.error?.code)
        assertEquals(listOf("future-1"), bridge.markedFailed)
    }

    private fun coordinator(
        bridge: QueueBridge,
        scheduler: FakeDispatchScheduler,
    ): ReminderScheduleCoordinator = ReminderScheduleCoordinator(
        nativeBridge = bridge,
        alarmScheduler = scheduler,
        deliveryService = ReminderDeliveryService(
            nativeBridge = bridge,
            notifications = NoopDisplayService,
            eventHub = NotificationEventHub(),
            logger = { _, _, _ -> },
            nowUtc = { Now.toString() },
        ),
        continuationEnqueuer = {},
        logger = { _, _, _ -> },
        now = { Now },
        elapsedRealtime = { 0L },
    )

    companion object {
        private val Now = Instant.parse("2026-07-05T00:00:00Z")
        private const val FutureAt = "2026-08-05T00:00:00Z"
    }
}

private class FakeDispatchScheduler(
    private val scheduleResult: ScheduleResult = ScheduleResult.Success,
) : DispatchAlarmScheduler {
    val scheduledAt = mutableListOf<String>()
    var cancelCount = 0

    override fun schedule(plannedAt: String): ScheduleResult {
        scheduledAt += plannedAt
        return scheduleResult
    }

    override fun cancel(): CancelResult {
        cancelCount += 1
        return CancelResult.Success
    }

    override fun canScheduleExactAlarms(): Boolean = true
}

private object NoopDisplayService : NotificationDisplayService {
    override fun post(content: ReminderNotificationContent, sentAt: String) = NotificationPostResult.Success(1)
    override fun cancel(reminderId: String) = Unit
}

private class QueueBridge(private val hasHead: Boolean) : NativeEventBridge {
    val markedScheduled = mutableListOf<String>()
    val markedFailed = mutableListOf<String>()

    override fun listSchedulableReminders(requestJson: String): String {
        val request = NativeContractJsonCodec.decodeObject(requestJson)
        val isDueQuery = request.containsKey("to_at") && !request.containsKey("from_at")
        val items = if (!isDueQuery && hasHead) listOf(reminder()) else emptyList()
        return success(
            linkedMapOf(
                "items" to items,
                "selected_count" to items.size,
                "has_more" to false,
                "next_cursor" to null,
                "unsupported_reminder_ids" to emptyList<String>(),
            ),
        )
    }

    override fun markReminderScheduled(requestJson: String): String {
        val id = NativeContractJsonCodec.decodeObject(requestJson)["id"] as String
        markedScheduled += id
        return success(reminder(status = "scheduled"))
    }

    override fun markReminderFailed(requestJson: String): String {
        val id = NativeContractJsonCodec.decodeObject(requestJson)["id"] as String
        markedFailed += id
        return success(reminder(status = "failed"))
    }

    private fun reminder(status: String = "pending") = linkedMapOf<String, Any?>(
        "id" to "future-1",
        "target_type" to "event",
        "target_id" to "event-1",
        "remind_at" to "2026-08-05T00:00:00Z",
        "methods" to listOf("popup"),
        "advance_minutes" to null,
        "message" to null,
        "is_enabled" to true,
        "status" to status,
        "scheduled_at" to null,
        "last_triggered_at" to null,
        "failure_reason" to null,
        "created_at" to "2026-07-01T00:00:00Z",
        "updated_at" to "2026-07-01T00:00:00Z",
        "deleted_at" to null,
    )

    private fun success(data: Any?): String = NativeContractJsonCodec.encodeObject(NativeResultContract.success(data).toMap())

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
    override fun getReminder(requestJson: String) = unsupported()
    override fun markReminderSent(requestJson: String) = unsupported()
    override fun enableReminder(requestJson: String) = unsupported()
    override fun disableReminder(requestJson: String) = unsupported()
    override fun createNotification(requestJson: String) = unsupported()
    override fun consumeReminderAfterDelivery(requestJson: String) = unsupported()
    private fun unsupported(): String = throw UnsupportedOperationException()
}
