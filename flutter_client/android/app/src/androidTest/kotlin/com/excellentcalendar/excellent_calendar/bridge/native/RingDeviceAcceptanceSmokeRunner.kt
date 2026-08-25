package com.excellentcalendar.excellent_calendar.bridge.native

import android.content.Context
import android.os.SystemClock
import com.excellentcalendar.excellent_calendar.android.alarm.ReminderCoordinatorFactory
import com.excellentcalendar.excellent_calendar.android.ring.RingRuntime
import com.excellentcalendar.excellent_calendar.android.ring.RingRuntimeProvider
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.ReconcileReminderScheduleContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderScheduleTrigger
import java.time.Instant
import java.time.temporal.ChronoUnit

/**
 * Device-only acceptance for the real AlarmManager -> Dispatcher -> JNI -> C++ -> RingRuntime chain.
 * Every created Event is soft-deleted in finally so this runner never leaves test reminders behind.
 */
internal object RingDeviceAcceptanceSmokeRunner {
    fun prepareRestart(context: Context): String {
        check(NativeContractRuntimeProfile.current == NativeContractProfile.V2)
        val bridge = AndroidNativeBridgeFactory.create(context)
        val runtime = RingRuntimeProvider.get(context)
        var eventId: String? = null
        var completed = false
        try {
            assertCapability(runtime)
            check(runtime.activeSession() == null) { "A pre-existing ring session blocks isolated acceptance" }
            eventId = createEvent(bridge, "DEVICE_RING_PROCESS_RESTART")
            val reminderId = createRingReminder(bridge, eventId, utcAfter(20))
            reconcile(context, ReminderScheduleTrigger.Mutation, "schedule process-restart reminder")
            val audible = await("pre-restart audible session", 75_000) {
                runtime.activeSession()?.takeIf { session ->
                    session.phase == "audible" &&
                        session.items.singleOrNull()?.reminderId == reminderId &&
                        session.items.single().finalizeOutcome == "sent" &&
                        (session.soundActive || session.vibrationActive)
                }
            }
            check(audible.audibleDeadlineAt != null) { "Audible session has no durable deadline" }
            val stored = context.getSharedPreferences(RestartPreferences, Context.MODE_PRIVATE).edit()
                .putString(RestartEventId, eventId)
                .putString(RestartReminderId, reminderId)
                .putString(RestartSessionId, audible.sessionId)
                .commit()
            check(stored) { "Could not persist device acceptance restart marker" }
            completed = true
            return "PASS ring restart prepare: active sent session persisted; instrumentation exit will kill its process"
        } finally {
            if (!completed) cleanup(context, bridge, runtime, listOfNotNull(eventId))
        }
    }

    fun verifyRestart(context: Context): String {
        check(NativeContractRuntimeProfile.current == NativeContractProfile.V2)
        val preferences = context.getSharedPreferences(RestartPreferences, Context.MODE_PRIVATE)
        val eventId = requireNotNull(preferences.getString(RestartEventId, null)) { "Missing restart Event marker" }
        val reminderId = requireNotNull(preferences.getString(RestartReminderId, null)) { "Missing restart Reminder marker" }
        val priorSessionId = requireNotNull(preferences.getString(RestartSessionId, null)) { "Missing restart session marker" }
        val bridge = AndroidNativeBridgeFactory.create(context)
        val runtime = RingRuntimeProvider.get(context)
        try {
            val recovered = await("recovered audible ring session", 30_000) {
                runtime.activeSession()?.takeIf { session ->
                    session.sessionId == priorSessionId &&
                        session.phase == "audible" &&
                        session.items.singleOrNull()?.reminderId == reminderId &&
                        session.items.single().finalizeOutcome == "sent" &&
                        session.controlNotificationVisible &&
                        (session.soundActive || session.vibrationActive)
                }
            }
            check(Instant.parse(requireNotNull(recovered.audibleDeadlineAt)).isAfter(Instant.now())) {
                "Recovered session resumed after its safety deadline"
            }
            runtime.stopFromNotification(recovered.items.map { it.deliveryId })
            check(runtime.activeSession() == null) { "Recovered session could not be stopped" }
            return "PASS ring restart verify: durable session recovered, output resumed within original deadline, stop succeeded"
        } finally {
            cleanup(context, bridge, runtime, listOf(eventId))
            preferences.edit().clear().commit()
        }
    }

    fun runQuick(context: Context): String {
        check(NativeContractRuntimeProfile.current == NativeContractProfile.V2)
        val bridge = AndroidNativeBridgeFactory.create(context)
        val runtime = RingRuntimeProvider.get(context)
        val createdEventIds = mutableListOf<String>()
        try {
            assertCapability(runtime)
            check(runtime.activeSession() == null) { "A pre-existing ring session blocks isolated acceptance" }

            val mergedEventId = createEvent(bridge, "DEVICE_RING_MERGED")
            createdEventIds += mergedEventId
            val mergedDueAt = utcAfter(20)
            val firstReminderId = createRingReminder(bridge, mergedEventId, mergedDueAt)
            val secondReminderId = createRingReminder(bridge, mergedEventId, mergedDueAt)
            reconcile(context, ReminderScheduleTrigger.Mutation, "schedule merged reminders")

            val merged = await("two merged audible ring items", 75_000) {
                runtime.activeSession()?.takeIf { session ->
                    session.phase == "audible" &&
                        session.items.map { it.reminderId }.toSet() == setOf(firstReminderId, secondReminderId) &&
                        session.controlNotificationVisible &&
                        (session.soundActive || session.vibrationActive) &&
                        session.items.all { it.finalizeOutcome == "sent" }
                }
            }
            val sourceDeliveryIds = merged.items.map { it.deliveryId }
            val snoozeStartedAt = Instant.now()
            val snoozed = runtime.snoozeFromNotification(sourceDeliveryIds)
            check(snoozed.ok) { "snooze all failed: ${snoozed.error}" }
            val snoozedReminderIds = snoozedReminderIds(snoozed.data)
            check(snoozedReminderIds.size == 2) { "snooze all did not commit both items: ${snoozed.data}" }
            check(runtime.activeSession() == null) { "Successful snooze items remained in the active session" }

            sourceDeliveryIds.zip(snoozedReminderIds).forEach { (deliveryId, expectedReminderId) ->
                val replay = successData(
                    bridge.snoozeReminder(json(linkedMapOf("source_delivery_id" to deliveryId))),
                    "replay reminder.snooze",
                )
                check(replay["idempotent_replay"] == true) { "C++ snooze replay was not idempotent: $replay" }
                val reminder = objectMap(replay["snoozed_reminder"], "snoozed_reminder")
                check(reminder["reminder_id"] == expectedReminderId) { "Snooze replay changed reminder identity" }
                check(reminder["methods"] == listOf("ring")) { "Snoozed reminder lost ring method" }
                val delaySeconds = ChronoUnit.SECONDS.between(snoozeStartedAt, Instant.parse(reminder["remind_at"] as String))
                check(delaySeconds in 595..605) { "Snooze was not fixed at 10 minutes: delay=$delaySeconds" }
            }
            val duplicateAction = runtime.snoozeFromNotification(sourceDeliveryIds)
            check(!duplicateAction.ok && duplicateAction.error?.code == NativeErrorCodes.RingItemNotFound) {
                "Repeated Android snooze did not reject removed items: $duplicateAction"
            }

            val liveEventId = createEvent(bridge, "DEVICE_RING_AFTER_SNOOZE")
            createdEventIds += liveEventId
            val liveReminderId = createRingReminder(bridge, liveEventId, utcAfter(20))
            reconcile(context, ReminderScheduleTrigger.Mutation, "schedule post-snooze reminder")
            val live = await("post-snooze ordinary reminder", 75_000) {
                runtime.activeSession()?.takeIf { session ->
                    session.phase == "audible" &&
                        session.items.size == 1 &&
                        session.items.single().reminderId == liveReminderId &&
                        session.items.single().finalizeOutcome == "sent"
                }
            }
            runtime.stopFromNotification(live.items.map { it.deliveryId })
            check(runtime.activeSession() == null) { "Stop did not clear the post-snooze session" }
            val delivered = successData(
                bridge.getReminder(json(linkedMapOf("reminder_id" to liveReminderId))),
                "get delivered reminder",
            )
            check(delivered["status"] == "sent") { "Post-snooze reminder was not finalized sent: $delivered" }

            return "PASS ring quick: two-item merge, snooze-all cleanup, C++ idempotency, " +
                "post-snooze live delivery, stop, and sent finalize"
        } finally {
            cleanup(context, bridge, runtime, createdEventIds)
        }
    }

    fun runFiveMinute(context: Context): String {
        check(NativeContractRuntimeProfile.current == NativeContractProfile.V2)
        val bridge = AndroidNativeBridgeFactory.create(context)
        val runtime = RingRuntimeProvider.get(context)
        val createdEventIds = mutableListOf<String>()
        try {
            assertCapability(runtime)
            check(runtime.activeSession() == null) { "A pre-existing ring session blocks isolated acceptance" }
            val eventId = createEvent(bridge, "DEVICE_RING_FIVE_MINUTE")
            createdEventIds += eventId
            val reminderId = createRingReminder(bridge, eventId, utcAfter(20))
            reconcile(context, ReminderScheduleTrigger.Mutation, "schedule five-minute reminder")
            val audible = await("five-minute reminder audible", 75_000) {
                runtime.activeSession()?.takeIf { session ->
                    session.phase == "audible" && session.items.singleOrNull()?.reminderId == reminderId &&
                        session.items.single().finalizeOutcome == "sent"
                }
            }
            val deadline = Instant.parse(requireNotNull(audible.audibleDeadlineAt))
            val quiet = await("five-minute automatic quiet transition", RingRuntime.MaxAudibleMillis + 30_000L) {
                runtime.activeSession()?.takeIf { session ->
                    session.phase == "quiet_pending" &&
                        !session.soundActive && !session.vibrationActive &&
                        session.controlNotificationVisible &&
                        session.items.singleOrNull()?.reminderId == reminderId
                }
            }
            check(!Instant.parse(requireNotNull(quiet.quietSince)).isBefore(deadline.minusSeconds(2))) {
                "Ring entered quiet before its five-minute deadline"
            }
            runtime.stopFromNotification(quiet.items.map { it.deliveryId })
            check(runtime.activeSession() == null) { "Five-minute quiet session could not be dismissed" }
            return "PASS ring five-minute: audible -> quiet_pending, outputs stopped, control retained, dismiss succeeded"
        } finally {
            cleanup(context, bridge, runtime, createdEventIds)
        }
    }

    private fun assertCapability(runtime: RingRuntime) {
        val state = successMap(runtime.state(), "ring.get_state")
        val capability = objectMap(state["capability"], "capability")
        check(capability["can_enable_ring"] == true) { "Ring capability is blocked: $capability" }
        check(capability["can_post_notifications"] == true) { "Notification capability is unavailable" }
        check(capability["can_schedule_exact_alarms"] == true) { "Exact alarm capability is unavailable" }
    }

    private fun createEvent(bridge: NativeCalendarCoreBridge, marker: String): String {
        val startAt = utcAfter(3_600)
        val endAt = Instant.parse(startAt).plusSeconds(3_600).toString()
        val event = successData(
            bridge.createEvent(
                json(
                    linkedMapOf(
                        "title" to marker,
                        "content" to null,
                        "start_at" to startAt,
                        "end_at" to endAt,
                        "start_date" to null,
                        "end_date" to null,
                        "is_all_day" to false,
                        "category_id" to null,
                        "importance" to null,
                        "location" to null,
                        "timezone" to "Asia/Shanghai",
                        "source" to "manual",
                        "recurrence" to null,
                        "reminders" to emptyList<Map<String, Any?>>(),
                    ),
                ),
            ),
            "event.create $marker",
        )
        return event["id"] as? String ?: error("event.create returned no id")
    }

    private fun createRingReminder(bridge: NativeCalendarCoreBridge, eventId: String, remindAt: String): String {
        val reminder = successData(
            bridge.createReminder(
                json(
                    linkedMapOf(
                        "target_type" to "event",
                        "target_id" to eventId,
                        "remind_at" to remindAt,
                        "advance_minutes" to null,
                        "methods" to listOf("ring"),
                        "message" to null,
                        "is_enabled" to true,
                        "source" to "manual",
                    ),
                ),
            ),
            "reminder.create ring",
        )
        return reminder["reminder_id"] as? String ?: error("reminder.create returned no id")
    }

    private fun reconcile(context: Context, trigger: ReminderScheduleTrigger, operation: String) {
        val result = ReminderCoordinatorFactory.create(context).reconcile(
            ReconcileReminderScheduleContract(trigger, force = true),
        )
        check(result.ok) { "$operation failed: ${result.error}" }
    }

    private fun cleanup(
        context: Context,
        bridge: NativeCalendarCoreBridge,
        runtime: RingRuntime,
        eventIds: List<String>,
    ) {
        runtime.activeSession()?.items?.map { it.deliveryId }?.takeIf { it.isNotEmpty() }?.let(runtime::stopFromNotification)
        eventIds.asReversed().forEach { eventId ->
            runCatching {
                successData(
                    bridge.deleteEvent(
                        json(
                            linkedMapOf(
                                "id" to eventId,
                                "delete_mode" to "soft",
                                "recurrence_delete_scope" to null,
                                "expected_recurrence_revision" to null,
                                "reason" to "device_acceptance_cleanup",
                            ),
                        ),
                    ),
                    "event.delete cleanup",
                )
            }
        }
        runCatching {
            ReminderCoordinatorFactory.create(context).reconcile(
                ReconcileReminderScheduleContract(ReminderScheduleTrigger.Mutation, force = true),
            )
        }
    }

    private fun snoozedReminderIds(data: Any?): List<String> {
        val map = objectMap(data, "ring snooze response")
        val results = map["results"] as? List<*> ?: error("ring snooze response has no results")
        return results.map { raw ->
            val item = objectMap(raw, "ring snooze result")
            check(item["status"] == "succeeded") { "ring snooze item failed: $item" }
            item["snoozed_reminder_id"] as? String ?: error("ring snooze result has no reminder id")
        }
    }

    private fun successData(json: String, operation: String): Map<String, Any?> {
        val result = NativeContractJsonCodec.decodeObject(json)
        check(result["ok"] == true && result["error"] == null) { "$operation failed: $result" }
        check(result["contract_version"] == 2) { "$operation returned the wrong Contract version" }
        return objectMap(result["data"], "$operation data")
    }

    private fun successMap(result: com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract, operation: String): Map<String, Any?> {
        check(result.ok) { "$operation failed: ${result.error}" }
        return objectMap(result.data, "$operation data")
    }

    @Suppress("UNCHECKED_CAST")
    private fun objectMap(value: Any?, parent: String): Map<String, Any?> =
        value as? Map<String, Any?> ?: error("$parent must be an object")

    private fun json(value: Map<String, Any?>): String = NativeContractJsonCodec.encodeObject(value)

    private fun utcAfter(seconds: Long): String = Instant.now().plusSeconds(seconds).truncatedTo(ChronoUnit.SECONDS).toString()

    private fun <T> await(label: String, timeoutMillis: Long, condition: () -> T?): T {
        val deadline = SystemClock.elapsedRealtime() + timeoutMillis
        var lastFailure: Throwable? = null
        while (SystemClock.elapsedRealtime() < deadline) {
            try {
                condition()?.let { return it }
            } catch (error: Throwable) {
                lastFailure = error
            }
            SystemClock.sleep(100)
        }
        throw AssertionError("Timed out waiting for $label", lastFailure)
    }

    private const val RestartPreferences = "ring_device_acceptance_v1"
    private const val RestartEventId = "event_id"
    private const val RestartReminderId = "reminder_id"
    private const val RestartSessionId = "session_id"
}
