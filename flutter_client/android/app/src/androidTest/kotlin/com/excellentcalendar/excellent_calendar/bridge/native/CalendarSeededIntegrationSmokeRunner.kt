package com.excellentcalendar.excellent_calendar.bridge.native

import android.content.Context
import com.excellentcalendar.excellent_calendar.BuildConfig
import com.excellentcalendar.excellent_calendar.bridge.channel.NativeBridgeLogger
import com.excellentcalendar.excellent_calendar.bridge.channel.NativeMethodChannelHandler
import com.excellentcalendar.excellent_calendar.bridge.channel.ResultDispatcher
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Seeds the application-id-isolated device-test store through real MethodChannel mutations, then
 * exercises the Calendar handler -> JNI -> C++ -> SQLite projection without touching release data.
 */
internal object CalendarSeededIntegrationSmokeRunner {
    fun run(context: Context): String {
        val applicationContext = context.applicationContext
        check(BuildConfig.CALENDAR_CORE_DEVICE_TEST)
        check(BuildConfig.APPLICATION_ID.endsWith(DeviceTestApplicationIdSuffix))
        check(applicationContext.packageName.endsWith(DeviceTestApplicationIdSuffix))
        check(BuildConfig.APPLICATION_ID == applicationContext.packageName)
        CalendarCoreDeviceTestSafetyGuard.verify(applicationContext)
        val bridge = AndroidNativeBridgeFactory.create(applicationContext)
        check(bridge is JniNativeCalendarCoreBridge) {
            "AndroidNativeBridgeFactory did not return the production JNI bridge"
        }
        val executor = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "calendar-seeded-integration")
        }
        val handler = NativeMethodChannelHandler(
            nativeCalendarCoreBridge = bridge,
            contractProfile = NativeContractProfile.V2,
            executor = executor,
            resultDispatcher = ResultDispatcher { block -> block() },
            logger = NativeBridgeLogger { _, _, _ -> },
        )

        val timezone = ZoneId.of(Timezone)
        val selectedDate = safeFutureDate(LocalDate.now(timezone))
        var event: EventSeed? = null
        var habit: HabitSeed? = null
        var anniversary: AnniversarySeed? = null
        var resultMessage: String? = null
        var primaryFailure: Throwable? = null
        try {
            event = seedEvent(handler, selectedDate, timezone)
            habit = seedHabit(handler, selectedDate)
            anniversary = seedAnniversary(handler, selectedDate)
            val counts = verifyCalendarProjection(
                handler = handler,
                selectedDate = selectedDate,
                event = event,
                habit = habit,
                anniversary = anniversary,
            )
            resultMessage = "PASS seeded Calendar MethodChannel/JNI/SQLite: 7-day snapshot, " +
                "typed Unicode sections=$counts, occurrence identities, device-test cleanup"
        } catch (error: Throwable) {
            primaryFailure = error
            throw error
        } finally {
            val cleanupFailures = mutableListOf<Throwable>()
            fun cleanup(operation: String, block: () -> Unit) {
                runCatching(block).onFailure { error ->
                    cleanupFailures += IllegalStateException("$operation failed", error)
                }
            }

            anniversary?.let { seed -> cleanup("anniversary.delete") { deleteAnniversary(handler, seed) } }
            habit?.let { seed -> cleanup("habit.delete") { deleteHabit(handler, seed) } }
            event?.let { seed -> cleanup("event.delete") { deleteEvent(handler, seed) } }
            handler.close()

            cleanupFailures.forEach { cleanupFailure ->
                if (primaryFailure != null) primaryFailure.addSuppressed(cleanupFailure)
            }
            if (primaryFailure == null && cleanupFailures.isNotEmpty()) throw cleanupFailures.first()
        }
        return requireNotNull(resultMessage)
    }

    private fun seedEvent(
        handler: NativeMethodChannelHandler,
        selectedDate: LocalDate,
        timezone: ZoneId,
    ): EventSeed {
        val start = selectedDate.atTime(EventLocalTime).atZone(timezone).toInstant().toString()
        val end = selectedDate.atTime(EventLocalTime.plusHours(1)).atZone(timezone).toInstant().toString()
        val data = invokeSuccess(
            handler,
            NativeMethodChannelHandler.MethodEventCreate,
            linkedMapOf(
                "title" to EventTitle,
                "content" to "真实 MethodChannel → JNI → C++ → SQLite",
                "start_at" to start,
                "end_at" to end,
                "start_date" to null,
                "end_date" to null,
                "is_all_day" to false,
                "category_id" to null,
                "importance" to "important_urgent",
                "location" to "集成测试室🧪",
                "timezone" to Timezone,
                "source" to "manual",
                "recurrence" to linkedMapOf(
                    "frequency" to "daily",
                    "interval" to 1,
                    "end_at" to null,
                    "count" to null,
                ),
                "reminders" to emptyList<Map<String, Any?>>(),
            ),
        )
        check(data["title"] == EventTitle && data["has_recurrence"] == true)
        return EventSeed(
            id = data["id"] as? String ?: error("event.create returned no id"),
            recurrenceRevision = (data["recurrence_revision"] as? Number)?.toLong()
                ?: error("event.create returned no recurrence revision"),
            occurrenceStartAt = start,
        )
    }

    private fun seedHabit(handler: NativeMethodChannelHandler, selectedDate: LocalDate): HabitSeed {
        val data = invokeSuccess(
            handler,
            NativeMethodChannelHandler.MethodHabitCreate,
            linkedMapOf(
                "title" to HabitTitle,
                "description" to "真实聚合习惯🗓️",
                "category_id" to null,
                "recurrence" to linkedMapOf(
                    "frequency" to "daily",
                    "interval" to 1,
                    "timezone_mode" to "follow_device",
                ),
                "target_count_hundredths" to null,
                "unit" to null,
                "start_date" to selectedDate.toString(),
                "end_date" to selectedDate.plusDays(30).toString(),
                "reminder" to linkedMapOf(
                    "is_enabled" to false,
                    "local_time" to null,
                    "timezone_mode" to "follow_device",
                    "method" to "popup",
                ),
                "timezone" to Timezone,
            ),
        )
        check(data["data_saved"] == true)
        val detail = objectMap(data["detail"], "habit.create.detail")
        val habit = objectMap(detail["habit"], "habit.create.detail.habit")
        check(habit["title"] == HabitTitle)
        return HabitSeed(
            id = habit["id"] as? String ?: error("habit.create returned no id"),
            expectedUpdatedAt = habit["updated_at"] as? String
                ?: error("habit.create returned no updated_at"),
        )
    }

    private fun seedAnniversary(handler: NativeMethodChannelHandler, selectedDate: LocalDate): AnniversarySeed {
        val sourceDate = selectedDate.minusYears(3)
        val data = invokeSuccess(
            handler,
            NativeMethodChannelHandler.MethodAnniversaryCreate,
            linkedMapOf(
                "title" to AnniversaryTitle,
                "date" to sourceDate.toString(),
                "calendar_type" to "solar",
                "category_id" to null,
                "recurrence" to linkedMapOf("frequency" to "yearly", "interval" to 1),
                "note" to "真实周年聚合🎉",
                "importance" to "important_noturgent",
                "timezone" to Timezone,
                "reminder_plan" to linkedMapOf(
                    "reminders_enabled" to false,
                    "templates" to emptyList<Map<String, Any?>>(),
                ),
            ),
        )
        check(data["data_saved"] == true)
        val detail = objectMap(data["detail"], "anniversary.create.detail")
        val anniversary = objectMap(detail["anniversary"], "anniversary.create.detail.anniversary")
        check(anniversary["title"] == AnniversaryTitle)
        return AnniversarySeed(
            id = anniversary["id"] as? String ?: error("anniversary.create returned no id"),
            sourceDate = sourceDate,
        )
    }

    private fun verifyCalendarProjection(
        handler: NativeMethodChannelHandler,
        selectedDate: LocalDate,
        event: EventSeed,
        habit: HabitSeed,
        anniversary: AnniversarySeed,
    ): Map<String, Int> {
        val rangeStart = selectedDate.minusDays(3)
        val rangeEnd = selectedDate.plusDays(4)
        val range = invokeSuccess(
            handler,
            NativeMethodChannelHandler.MethodCalendarRangeSummary,
            linkedMapOf(
                "range_start_date" to rangeStart.toString(),
                "range_end_date" to rangeEnd.toString(),
                "timezone" to Timezone,
            ),
        )
        val days = list(range["days"], "calendar.range_summary.days")
        check(days.size == 7)
        val selectedSummary = days.mapIndexed { index, value ->
            objectMap(value, "calendar.range_summary.days[$index]")
        }.single { it["date"] == selectedDate.toString() }
        check(
            selectedSummary["has_open_event"] == true &&
                selectedSummary["has_pending_habit"] == true &&
                selectedSummary["has_anniversary"] == true,
        ) { "Selected day did not aggregate all three seeded types: $selectedSummary" }
        val snapshot = range["snapshot_token"] as? String
            ?: error("calendar.range_summary returned no snapshot_token")

        val pages = listOf("event", "habit", "anniversary").associateWith { section ->
            invokeSuccess(
                handler,
                NativeMethodChannelHandler.MethodCalendarListDayItems,
                linkedMapOf(
                    "date" to selectedDate.toString(),
                    "timezone" to Timezone,
                    "section" to section,
                    "snapshot_token" to snapshot,
                    "cursor" to null,
                    "page_size" to 100,
                ),
            ).also { page ->
                check(page["snapshot_token"] == snapshot)
                check(page["date"] == selectedDate.toString() && page["section"] == section)
                check(list(page["items"], "calendar.list_day_items[$section].items").isNotEmpty())
            }
        }

        val eventItem = seededItem(pages.getValue("event"), "event_id", event.id, "event")
        check(eventItem["title"] == EventTitle && eventItem["is_recurring"] == true)
        check((eventItem["recurrence_revision"] as? Number)?.toLong() == event.recurrenceRevision)
        check(eventItem["occurrence_key"] is String)
        check(eventItem["occurrence_start_at"] == event.occurrenceStartAt)
        check(eventItem["occurrence_start_date"] == null)
        check(eventItem["day_display"] == "starts_at" && eventItem["display_local_time"] == "09:15")

        val habitItem = seededItem(pages.getValue("habit"), "habit_id", habit.id, "habit")
        check(habitItem["title"] == HabitTitle && habitItem["date"] == selectedDate.toString())

        val anniversaryItem = seededItem(
            pages.getValue("anniversary"),
            "anniversary_id",
            anniversary.id,
            "anniversary",
        )
        check(anniversaryItem["title"] == AnniversaryTitle)
        check(anniversaryItem["occurrence_key"] is String)
        check(anniversaryItem["occurrence_date"] == selectedDate.toString())
        check(anniversaryItem["source_date"] == anniversary.sourceDate.toString())
        check(anniversaryItem["is_repeating"] == true)

        return pages.mapValues { (section, page) ->
            list(page["items"], "calendar.list_day_items[$section].items").size
        }
    }

    private fun seededItem(
        page: Map<String, Any?>,
        idField: String,
        expectedId: String,
        section: String,
    ): Map<String, Any?> = list(page["items"], "calendar.list_day_items[$section].items")
        .mapIndexed { index, value -> objectMap(value, "calendar.list_day_items[$section].items[$index]") }
        .singleOrNull { item -> item[idField] == expectedId }
        ?: error("Calendar $section page did not contain seeded identity $expectedId")

    private fun deleteEvent(handler: NativeMethodChannelHandler, seed: EventSeed) {
        invokeSuccess(
            handler,
            NativeMethodChannelHandler.MethodEventDelete,
            linkedMapOf(
                "id" to seed.id,
                "delete_mode" to "soft",
                "recurrence_delete_scope" to "all_occurrences",
                "expected_recurrence_revision" to seed.recurrenceRevision,
                "reason" to "calendar_seeded_integration_cleanup",
            ),
        )
    }

    private fun deleteHabit(handler: NativeMethodChannelHandler, seed: HabitSeed) {
        invokeSuccess(
            handler,
            NativeMethodChannelHandler.MethodHabitDelete,
            linkedMapOf(
                "id" to seed.id,
                "expected_updated_at" to seed.expectedUpdatedAt,
                "timezone" to Timezone,
            ),
        )
    }

    private fun deleteAnniversary(handler: NativeMethodChannelHandler, seed: AnniversarySeed) {
        invokeSuccess(
            handler,
            NativeMethodChannelHandler.MethodAnniversaryDelete,
            linkedMapOf("id" to seed.id),
        )
    }

    private fun invokeSuccess(
        handler: NativeMethodChannelHandler,
        method: String,
        arguments: Map<String, Any?>,
    ): Map<String, Any?> {
        val result = AwaitedResult()
        handler.onMethodCall(MethodCall(method, arguments), result)
        check(result.completed.await(20, TimeUnit.SECONDS)) { "$method did not complete" }
        check(!result.errorCalled && !result.notImplementedCalled) { "$method bypassed NativeResult" }
        return successData(result.value, method)
    }

    private fun successData(value: Any?, operation: String): Map<String, Any?> {
        val result = objectMap(value, "$operation.NativeResult")
        check(result.keys == setOf("ok", "data", "error", "contract_version", "request_id"))
        check(result["ok"] == true && result["error"] == null) { "$operation failed: $result" }
        check((result["contract_version"] as? Number)?.toInt() == 2)
        check(result["request_id"] is String)
        return objectMap(result["data"], "$operation.data")
    }

    private fun objectMap(value: Any?, parent: String): Map<String, Any?> {
        val map = value as? Map<*, *> ?: error("$parent must be an object")
        return buildMap {
            map.forEach { (key, entry) ->
                check(key is String) { "$parent contains a non-string key" }
                put(key, entry)
            }
        }
    }

    private fun list(value: Any?, parent: String): List<*> =
        value as? List<*> ?: error("$parent must be an array")

    private fun safeFutureDate(today: LocalDate): LocalDate {
        val tomorrow = today.plusDays(1)
        return if (tomorrow.monthValue == 2 && tomorrow.dayOfMonth == 29) tomorrow.plusDays(1) else tomorrow
    }

    private data class EventSeed(
        val id: String,
        val recurrenceRevision: Long,
        val occurrenceStartAt: String,
    )

    private data class HabitSeed(val id: String, val expectedUpdatedAt: String)

    private data class AnniversarySeed(val id: String, val sourceDate: LocalDate)

    private class AwaitedResult : MethodChannel.Result {
        val completed = CountDownLatch(1)
        var value: Any? = null
            private set
        var errorCalled = false
            private set
        var notImplementedCalled = false
            private set

        override fun success(result: Any?) {
            value = result
            completed.countDown()
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            errorCalled = true
            completed.countDown()
        }

        override fun notImplemented() {
            notImplementedCalled = true
            completed.countDown()
        }
    }

    private const val DeviceTestApplicationIdSuffix = ".device_test"
    private const val Timezone = "Asia/Shanghai"
    private const val EventTitle = "Calendar 集成事件🗓️"
    private const val HabitTitle = "Calendar 集成习惯📚"
    private const val AnniversaryTitle = "Calendar 集成周年🎉"
    private val EventLocalTime = LocalTime.of(9, 15)
}
