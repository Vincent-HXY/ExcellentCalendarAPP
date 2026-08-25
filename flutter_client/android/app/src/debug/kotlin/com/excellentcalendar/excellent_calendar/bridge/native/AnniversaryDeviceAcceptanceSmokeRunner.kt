package com.excellentcalendar.excellent_calendar.bridge.native

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.SystemClock
import com.excellentcalendar.excellent_calendar.android.alarm.ReminderCoordinatorFactory
import com.excellentcalendar.excellent_calendar.android.alarm.ReminderDispatchAlarmScheduler
import com.excellentcalendar.excellent_calendar.android.notification.AndroidNotificationRuntime
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.ReconcileReminderScheduleContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderScheduleTrigger
import com.excellentcalendar.excellent_calendar.bridge.runtime.AndroidDeviceTimezoneProvider
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

/**
 * Physical-device acceptance for Anniversary Alarm -> Notification -> tap.
 *
 * The prepare and verify phases deliberately run in different app processes.
 * The caller kills the app process after prepare; AlarmManager must restore it
 * to deliver the notification from the durable C++ queue.
 */
internal object AnniversaryDeviceAcceptanceSmokeRunner {
    fun prepareAlarm(context: Context): String {
        requireNotificationPermission(context)
        check(ReminderDispatchAlarmScheduler(context).canScheduleExactAlarms()) {
            "Exact alarm access is required for deterministic physical-device acceptance"
        }
        val preferences = context.getSharedPreferences(Preferences, Context.MODE_PRIVATE)
        check(!preferences.contains(AnniversaryId)) {
            "A prior Anniversary alarm acceptance marker still exists; run verify cleanup first"
        }

        val timezone = AndroidDeviceTimezoneProvider.currentTimezone()
        val zone = ZoneId.of(timezone)
        val due = ZonedDateTime.now(zone)
            .plusMinutes(2)
            .withSecond(0)
            .withNano(0)
        val title = "$TitlePrefix${System.currentTimeMillis()}"
        val bridge = AndroidNativeBridgeFactory.create(context)
        val storageDirectory = CalendarCoreV2StorageDirectoryResolver.resolve(context.filesDir)
        var anniversaryId: String? = null
        try {
            val created = successData(
                bridge.createAnniversary(
                    json(
                        linkedMapOf(
                            "title" to title,
                            "date" to due.toLocalDate().minusYears(3).toString(),
                            "calendar_type" to "solar",
                            "category_id" to null,
                            "recurrence" to linkedMapOf("frequency" to "yearly", "interval" to 1),
                            "note" to SecretNote,
                            "importance" to "important_urgent",
                            "timezone" to timezone,
                            "reminder_plan" to linkedMapOf(
                                "reminders_enabled" to true,
                                "templates" to listOf(
                                    linkedMapOf(
                                        "advance_days" to 0,
                                        "local_time" to due.format(LocalTimeFormat),
                                        "method" to "popup",
                                        "is_enabled" to true,
                                    ),
                                ),
                            ),
                        ),
                    ),
                ),
                "anniversary.create device alarm",
            )
            val anniversary = objectMap(created["anniversary"], "anniversary.create.data.anniversary")
            anniversaryId = anniversary["id"] as? String
                ?: error("anniversary.create returned no id")

            val reconciled = ReminderCoordinatorFactory.create(context).reconcile(
                ReconcileReminderScheduleContract(ReminderScheduleTrigger.Mutation, force = true),
            )
            check(reconciled.ok) { "Anniversary alarm reconciliation failed: ${reconciled.error}" }

            val original = reminderRecords(storageDirectory).single { record ->
                record["target_type"] == "anniversary" &&
                    record["target_id"] == anniversaryId &&
                    record["occurrence_date"] == due.toLocalDate().toString() &&
                    record["deleted_at"] == null
            }
            val reminderId = original["reminder_id"] as? String
                ?: error("Materialized Anniversary Reminder has no id")
            val occurrenceKey = original["occurrence_key"] as? String
                ?: error("Materialized Anniversary Reminder has no occurrence identity")
            val templateKey = original["template_key"] as? String
                ?: error("Materialized Anniversary Reminder has no template identity")
            val remindAt = original["remind_at"] as? String
                ?: error("Materialized Anniversary Reminder has no UTC remind_at")
            check(Instant.parse(remindAt) == due.toInstant()) {
                "Materialized UTC remind_at changed the requested local-time intent"
            }
            check(original["status"] == "scheduled" && original["scheduled_at"] is String) {
                "Materialized Anniversary Reminder was not marked scheduled: $original"
            }
            check(
                preferences.edit()
                    .putString(AnniversaryId, anniversaryId)
                    .putString(ReminderId, reminderId)
                    .putString(OccurrenceKey, occurrenceKey)
                    .putString(TemplateKey, templateKey)
                    .putString(RemindAt, remindAt)
                    .putString(Title, title)
                    .commit(),
            ) { "Could not persist Anniversary alarm acceptance marker" }
            return "PASS Anniversary alarm prepared id=$anniversaryId reminder=$reminderId " +
                "local=${due.toLocalDate()}T${due.format(LocalTimeFormat)} timezone=$timezone utc=$remindAt"
        } catch (error: Throwable) {
            anniversaryId?.let { id -> cleanupAnniversary(context, bridge, id) }
            throw error
        }
    }

    fun verifyAlarm(context: Context): String {
        requireNotificationPermission(context)
        val preferences = context.getSharedPreferences(Preferences, Context.MODE_PRIVATE)
        val anniversaryId = requiredMarker(preferences.getString(AnniversaryId, null), AnniversaryId)
        val reminderId = requiredMarker(preferences.getString(ReminderId, null), ReminderId)
        val occurrenceKey = requiredMarker(preferences.getString(OccurrenceKey, null), OccurrenceKey)
        val templateKey = requiredMarker(preferences.getString(TemplateKey, null), TemplateKey)
        val remindAt = requiredMarker(preferences.getString(RemindAt, null), RemindAt)
        val title = requiredMarker(preferences.getString(Title, null), Title)
        val bridge = AndroidNativeBridgeFactory.create(context)
        val storageDirectory = CalendarCoreV2StorageDirectoryResolver.resolve(context.filesDir)
        val notificationManager = context.getSystemService(NotificationManager::class.java)
        var deliveredTag: String? = null
        try {
            val delivered = await("Anniversary system notification", 30_000) {
                notificationManager.activeNotifications.firstOrNull { item ->
                    item.tag?.startsWith("delivery:") == true &&
                        item.notification.extras
                            .getCharSequence(Notification.EXTRA_TITLE)
                            ?.contains(title) == true
                }
            }
            deliveredTag = delivered.tag
            val deliveryId = delivered.tag.removePrefix("delivery:")
            check(deliveryId.isNotBlank()) { "Anniversary notification has no stable delivery tag" }
            val displayedTitle = delivered.notification.extras
                .getCharSequence(Notification.EXTRA_TITLE)
                ?.toString()
                ?: error("Anniversary notification has no frozen title")
            val displayedBody = delivered.notification.extras
                .getCharSequence(Notification.EXTRA_TEXT)
                ?.toString()
                .orEmpty()
            val expectedBody = "今天是“$title”"
            check(displayedBody == expectedBody) {
                "On-time Anniversary notification used the wrong copy: $displayedBody"
            }
            check(SecretNote !in displayedTitle && SecretNote !in displayedBody) {
                "Anniversary lock-screen notification leaked the note"
            }

            val records = reminderRecords(storageDirectory)
            val original = records.single { it["reminder_id"] == reminderId }
            check(original["status"] == "sent") { "Original Anniversary Reminder is not sent: $original" }
            check(original["fulfillment_delivery_id"] == deliveryId) {
                "Reminder and Android Notification do not share delivery identity"
            }
            check(original["occurrence_key"] == occurrenceKey && original["remind_at"] == remindAt) {
                "Delivered Reminder identity changed after the process restart"
            }
            val successor = records.single { record ->
                record["target_type"] == "anniversary" &&
                    record["target_id"] == anniversaryId &&
                    record["template_key"] == templateKey &&
                    record["reminder_id"] != reminderId &&
                    record["deleted_at"] == null
            }
            check(successor["occurrence_key"] != occurrenceKey) {
                "Annual successor reused the prior occurrence identity"
            }
            check(Instant.parse(successor["remind_at"] as String).isAfter(Instant.parse(remindAt))) {
                "Annual successor is not later than the delivered Reminder"
            }

            val notificationRecord = notificationRecords(storageDirectory).single { record ->
                record["delivery_id"] == deliveryId
            }
            check(
                notificationRecord["target_type"] == "anniversary" &&
                    notificationRecord["target_id"] == anniversaryId &&
                    notificationRecord["occurrence_key"] == occurrenceKey &&
                    notificationRecord["kind"] == "reminder" &&
                    notificationRecord["body"] == expectedBody &&
                    notificationRecord["status"] == "sent",
            ) { "Persisted Anniversary Notification identity is invalid: $notificationRecord" }

            AndroidNotificationRuntime.tapPayloadStore.clear()
            delivered.notification.contentIntent.send()
            val tapPayload = await("Anniversary notification tap payload", 15_000) {
                AndroidNotificationRuntime.tapPayloadStore.take()
            }
            check(
                tapPayload["notification_id"] == notificationRecord["notification_id"] &&
                    tapPayload["delivery_id"] == deliveryId &&
                    tapPayload["target_type"] == "anniversary" &&
                    tapPayload["target_id"] == anniversaryId &&
                    tapPayload["occurrence_key"] == occurrenceKey &&
                    tapPayload["route"] == "anniversary.detail",
            ) { "Anniversary notification tap identity is invalid: $tapPayload" }

            delivered.notification.contentIntent.send()
            SystemClock.sleep(500)
            check(AndroidNotificationRuntime.tapPayloadStore.take() == null) {
                "Repeated Anniversary notification tap was not deduplicated"
            }
            return "PASS process-death Alarm -> one Notification -> deduplicated tap; " +
                "delivery=$deliveryId successor=${successor["reminder_id"]}"
        } finally {
            cleanupAnniversary(context, bridge, anniversaryId)
            deliveredTag?.let { tag -> notificationManager.cancel(tag, NotificationId) }
            preferences.edit().clear().commit()
        }
    }

    private fun cleanupAnniversary(
        context: Context,
        bridge: NativeCalendarCoreBridge,
        anniversaryId: String,
    ) {
        val result = decode(bridge.deleteAnniversary(json(linkedMapOf("id" to anniversaryId))))
        if (result["ok"] == true) {
            ReminderCoordinatorFactory.create(context).reconcile(
                ReconcileReminderScheduleContract(ReminderScheduleTrigger.Mutation, force = true),
            )
        }
    }

    private fun reminderRecords(storageDirectory: File): List<Map<String, Any?>> =
        records(storageDirectory, "reminders.json", "reminders")

    private fun notificationRecords(storageDirectory: File): List<Map<String, Any?>> =
        records(storageDirectory, "notifications.json", "notifications")

    private fun records(
        storageDirectory: File,
        fileName: String,
        collection: String,
    ): List<Map<String, Any?>> {
        val root = decode(File(storageDirectory, fileName).readText())
        check((root["storage_version"] as Number).toInt() == 3) {
            "$fileName is not strict Storage v3"
        }
        return (root[collection] as? List<*>)?.mapIndexed { index, value ->
            objectMap(value, "$fileName.$collection[$index]")
        } ?: error("$fileName has no $collection collection")
    }

    private fun successData(json: String, operation: String): Map<String, Any?> {
        val result = decode(json)
        check(result["ok"] == true && result["error"] == null) {
            "$operation failed: $result"
        }
        return objectMap(result["data"], "$operation.data")
    }

    @Suppress("UNCHECKED_CAST")
    private fun objectMap(value: Any?, field: String): Map<String, Any?> =
        value as? Map<String, Any?> ?: error("$field is not an object")

    private fun json(value: Map<String, Any?>): String = NativeContractJsonCodec.encodeObject(value)

    private fun decode(value: String): Map<String, Any?> = NativeContractJsonCodec.decodeObject(value)

    private fun requireNotificationPermission(context: Context) {
        check(
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED,
        ) { "POST_NOTIFICATIONS must be granted before device acceptance" }
        check(context.getSystemService(NotificationManager::class.java).areNotificationsEnabled()) {
            "App notifications are disabled in Android settings"
        }
    }

    private fun requiredMarker(value: String?, name: String): String =
        requireNotNull(value) { "Missing Anniversary alarm acceptance marker: $name" }

    private fun <T> await(label: String, timeoutMillis: Long, block: () -> T?): T {
        val deadline = SystemClock.elapsedRealtime() + timeoutMillis
        while (SystemClock.elapsedRealtime() < deadline) {
            block()?.let { return it }
            SystemClock.sleep(100)
        }
        error("Timed out waiting for $label")
    }

    private val LocalTimeFormat = DateTimeFormatter.ofPattern("HH:mm")
    private const val Preferences = "anniversary_device_acceptance"
    private const val AnniversaryId = "anniversary_id"
    private const val ReminderId = "reminder_id"
    private const val OccurrenceKey = "occurrence_key"
    private const val TemplateKey = "template_key"
    private const val RemindAt = "remind_at"
    private const val Title = "title"
    private const val TitlePrefix = "DEVICE_ANNIVERSARY_ALARM_"
    private const val SecretNote = "DEVICE_SECRET_NOTE_MUST_NOT_APPEAR"
    private const val NotificationId = 1
}
