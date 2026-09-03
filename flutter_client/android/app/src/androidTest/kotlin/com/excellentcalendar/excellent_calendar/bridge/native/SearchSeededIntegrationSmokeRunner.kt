package com.excellentcalendar.excellent_calendar.bridge.native

import android.content.Context
import com.excellentcalendar.excellent_calendar.BuildConfig
import com.excellentcalendar.excellent_calendar.bridge.channel.NativeBridgeLogger
import com.excellentcalendar.excellent_calendar.bridge.channel.NativeMethodChannelHandler
import com.excellentcalendar.excellent_calendar.bridge.channel.ResultDispatcher
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Seeds all three canonical Stores, runs the real Search handler/JNI/C++ query, then cleans up. */
internal object SearchSeededIntegrationSmokeRunner {
    fun run(context: Context): String {
        val appContext = context.applicationContext
        check(BuildConfig.CALENDAR_CORE_DEVICE_TEST)
        check(BuildConfig.APPLICATION_ID.endsWith(DeviceTestApplicationIdSuffix))
        check(appContext.packageName == BuildConfig.APPLICATION_ID)
        CalendarCoreDeviceTestSafetyGuard.verify(appContext)
        val bridge = AndroidNativeBridgeFactory.create(appContext)
        check(bridge is JniNativeCalendarCoreBridge)
        val executor = Executors.newSingleThreadExecutor { runnable -> Thread(runnable, "search-seeded-integration") }
        val handler = NativeMethodChannelHandler(
            nativeCalendarCoreBridge = bridge,
            contractProfile = NativeContractProfile.V2,
            executor = executor,
            resultDispatcher = ResultDispatcher { it() },
            logger = NativeBridgeLogger { _, _, _ -> },
        )
        val selectedDate = LocalDate.now(ZoneId.of(Timezone)).plusDays(2)
        var event: EventSeed? = null
        var habit: HabitSeed? = null
        var anniversaryId: String? = null
        var primaryFailure: Throwable? = null
        try {
            deleteSeededAnniversaries(bridge, knownId = null)
            event = seedEvent(bridge, selectedDate)
            habit = seedHabit(bridge, selectedDate)
            anniversaryId = seedAnniversary(bridge, selectedDate) { createdId ->
                anniversaryId = createdId
            }
            val response = invokeSuccess(handler, NativeMethodChannelHandler.MethodSearchQuery, queryRequest())
            check((response["query_generation"] as? Number)?.toLong() == QueryGeneration)
            check(response["normalized_keyword"] == MarkerKeyword)
            check(response["timezone"] == Timezone)
            val sections = list(response["sections"], "search.query.sections")
                .mapIndexed { index, value -> objectMap(value, "search.query.sections[$index]") }
            check(sections.map { it["target_type"] } == TargetTypes)
            val expected = mapOf(
                "event" to event.id,
                "habit" to habit.id,
                "anniversary" to anniversaryId,
            )
            sections.forEach { section ->
                val target = section["target_type"] as String
                val items = list(section["items"], "search.query.$target.items")
                    .mapIndexed { index, value -> objectMap(value, "search.query.$target.items[$index]") }
                check(items.any { it["target_type"] == target && it["target_id"] == expected.getValue(target) }) {
                    "Search $target section did not contain its seeded identity"
                }
            }
        } catch (error: Throwable) {
            primaryFailure = error
            throw error
        } finally {
            val cleanupFailures = mutableListOf<Throwable>()
            fun cleanup(name: String, block: () -> Unit) {
                runCatching(block).onFailure { cleanupFailures += IllegalStateException("$name cleanup failed", it) }
            }
            cleanup("anniversary") { deleteSeededAnniversaries(bridge, anniversaryId) }
            habit?.let { seed -> cleanup("habit") { deleteHabit(bridge, seed) } }
            event?.let { seed -> cleanup("event") { deleteEvent(bridge, seed) } }
            handler.close()
            cleanupFailures.forEach { if (primaryFailure != null) primaryFailure.addSuppressed(it) }
            if (primaryFailure == null && cleanupFailures.isNotEmpty()) throw cleanupFailures.first()
        }
        return "PASS seeded Search MethodChannel/JNI/SQLite: Event+Habit+Anniversary Unicode query, typed sections, cleanup"
    }

    private fun seedEvent(bridge: NativeCalendarCoreBridge, date: LocalDate): EventSeed {
        val zone = ZoneId.of(Timezone)
        val start = date.atTime(LocalTime.of(10, 30)).atZone(zone).toInstant().toString()
        val end = date.atTime(LocalTime.of(11, 30)).atZone(zone).toInstant().toString()
        val data = successData(
            bridge.createEvent(
                json(
                    linkedMapOf(
                        "title" to "$MarkerKeyword Event😀",
                        "content" to "真实 Search JNI",
                        "start_at" to start,
                        "end_at" to end,
                        "start_date" to null,
                        "end_date" to null,
                        "is_all_day" to false,
                        "category_id" to null,
                        "importance" to "important_urgent",
                        "location" to "搜索集成室",
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
                ),
            ),
            "event.create",
        )
        return EventSeed(
            data["id"] as? String ?: error("event.create returned no id"),
            (data["recurrence_revision"] as? Number)?.toLong() ?: error("event.create returned no revision"),
        )
    }

    private fun seedHabit(bridge: NativeCalendarCoreBridge, date: LocalDate): HabitSeed {
        val data = successData(
            bridge.createHabit(
                json(
                    linkedMapOf(
                        "title" to "$MarkerKeyword Habit📚",
                        "description" to "真实 Search JNI",
                        "category_id" to null,
                        "recurrence" to linkedMapOf(
                            "frequency" to "daily",
                            "interval" to 1,
                            "timezone_mode" to "follow_device",
                        ),
                        "target_count_hundredths" to null,
                        "unit" to null,
                        "start_date" to date.toString(),
                        "end_date" to date.plusDays(30).toString(),
                        "reminder" to linkedMapOf(
                            "is_enabled" to false,
                            "local_time" to null,
                            "timezone_mode" to "follow_device",
                            "method" to "popup",
                        ),
                        "timezone" to Timezone,
                    ),
                ),
            ),
            "habit.create",
        )
        val detail = objectMap(data["detail"], "habit.create.detail")
        val habit = objectMap(detail["habit"], "habit.create.detail.habit")
        return HabitSeed(
            habit["id"] as? String ?: error("habit.create returned no id"),
            habit["updated_at"] as? String ?: error("habit.create returned no updated_at"),
        )
    }

    private fun seedAnniversary(
        bridge: NativeCalendarCoreBridge,
        date: LocalDate,
        onCreated: (String) -> Unit,
    ): String {
        val data = successData(
            bridge.createAnniversary(
                json(
                    linkedMapOf(
                        "title" to AnniversaryTitle,
                        "date" to date.minusYears(2).toString(),
                        "calendar_type" to "solar",
                        "category_id" to null,
                        "recurrence" to linkedMapOf("frequency" to "yearly", "interval" to 1),
                        "note" to "真实 Search JNI",
                        "importance" to "important_noturgent",
                        "timezone" to Timezone,
                        "reminder_plan" to linkedMapOf(
                            "reminders_enabled" to false,
                            "templates" to emptyList<Map<String, Any?>>(),
                        ),
                    ),
                ),
            ),
            "anniversary.create",
        )
        val anniversary = objectMap(data["anniversary"], "anniversary.create.anniversary")
        val id = anniversary["id"] as? String ?: error("anniversary.create returned no id")
        onCreated(id)
        return id
    }

    private fun deleteEvent(bridge: NativeCalendarCoreBridge, seed: EventSeed) {
        successData(
            bridge.deleteEvent(
                json(
                    linkedMapOf(
                        "id" to seed.id,
                        "delete_mode" to "soft",
                        "recurrence_delete_scope" to "all_occurrences",
                        "expected_recurrence_revision" to seed.recurrenceRevision,
                        "reason" to "search_seeded_integration_cleanup",
                    ),
                ),
            ),
            "event.delete",
        )
    }

    private fun deleteHabit(bridge: NativeCalendarCoreBridge, seed: HabitSeed) {
        successData(
            bridge.deleteHabit(
                json(
                    linkedMapOf(
                        "id" to seed.id,
                        "expected_updated_at" to seed.updatedAt,
                        "timezone" to Timezone,
                    ),
                ),
            ),
            "habit.delete",
        )
    }

    private fun deleteAnniversary(bridge: NativeCalendarCoreBridge, id: String) {
        successData(bridge.deleteAnniversary(json(linkedMapOf("id" to id))), "anniversary.delete")
    }

    private fun deleteSeededAnniversaries(bridge: NativeCalendarCoreBridge, knownId: String?) {
        val ids = linkedSetOf<String>()
        knownId?.let(ids::add)
        val discoveryFailure = runCatching {
            ids += findSeededAnniversaryIds(bridge)
        }.exceptionOrNull()
        val deleteFailures = mutableListOf<Throwable>()
        ids.forEach { id ->
            runCatching { deleteAnniversary(bridge, id) }
                .onFailure { deleteFailures += IllegalStateException("anniversary.delete failed for $id", it) }
        }
        discoveryFailure?.let { deleteFailures.add(0, it) }
        if (deleteFailures.isNotEmpty()) {
            deleteFailures.drop(1).forEach(deleteFailures.first()::addSuppressed)
            throw deleteFailures.first()
        }
    }

    private fun findSeededAnniversaryIds(bridge: NativeCalendarCoreBridge): Set<String> {
        val ids = linkedSetOf<String>()
        var page = 1
        do {
            check(page <= MaxAnniversaryCleanupPages) { "anniversary cleanup pagination did not terminate" }
            val data = successData(
                bridge.listAnniversaries(
                    json(
                        linkedMapOf(
                            "timezone" to Timezone,
                            "pagination" to linkedMapOf(
                                "page" to page,
                                "page_size" to AnniversaryCleanupPageSize,
                                "cursor" to null,
                            ),
                            "sort_by" to "target_occurrence_date",
                            "sort_direction" to "asc",
                        ),
                    ),
                ),
                "anniversary.list",
            )
            list(data["items"], "anniversary.list.items").forEachIndexed { index, value ->
                val summary = objectMap(value, "anniversary.list.items[$index]")
                val anniversary = objectMap(
                    summary["anniversary"],
                    "anniversary.list.items[$index].anniversary",
                )
                if (anniversary["title"] == AnniversaryTitle) {
                    ids += anniversary["id"] as? String
                        ?: error("anniversary.list seeded item returned no id")
                }
            }
            val pagination = objectMap(data["pagination"], "anniversary.list.pagination")
            val hasMore = pagination["has_more"] as? Boolean
                ?: error("anniversary.list.pagination.has_more must be a boolean")
            if (!hasMore) break
            page += 1
        } while (true)
        return ids
    }

    private fun queryRequest(): Map<String, Any?> = linkedMapOf(
        "query_generation" to QueryGeneration,
        "keyword" to MarkerKeyword,
        "timezone" to Timezone,
        "target_types" to TargetTypes,
        "date_from" to null,
        "date_to_exclusive" to null,
        "category_ids" to null,
        "include_uncategorized" to false,
        "include_completed" to true,
        "sort_by" to "relevance",
        "sections" to TargetTypes.map { target ->
            linkedMapOf("target_type" to target, "page_size" to 20, "cursor" to null)
        },
    )

    private fun invokeSuccess(
        handler: NativeMethodChannelHandler,
        method: String,
        arguments: Map<String, Any?>,
    ): Map<String, Any?> {
        val result = AwaitedResult()
        handler.onMethodCall(MethodCall(method, arguments), result)
        check(result.completed.await(30, TimeUnit.SECONDS)) { "$method did not complete" }
        check(!result.errorCalled && !result.notImplementedCalled)
        return successData(result.value, method)
    }

    private fun successData(value: Any?, operation: String): Map<String, Any?> {
        val result = when (value) {
            is String -> NativeContractJsonCodec.decodeObject(value)
            else -> objectMap(value, "$operation.NativeResult")
        }
        check(result.keys == setOf("ok", "data", "error", "contract_version", "request_id"))
        check(result["ok"] == true && result["error"] == null) { "$operation failed: $result" }
        check((result["contract_version"] as? Number)?.toInt() == 2)
        return objectMap(result["data"], "$operation.data")
    }

    private fun json(value: Map<String, Any?>): String = NativeContractJsonCodec.encodeObject(value)

    private fun objectMap(value: Any?, parent: String): Map<String, Any?> {
        val source = value as? Map<*, *> ?: error("$parent must be an object")
        return buildMap {
            source.forEach { (key, item) ->
                check(key is String)
                put(key, item)
            }
        }
    }

    private fun list(value: Any?, parent: String): List<*> = value as? List<*> ?: error("$parent must be an array")

    private data class EventSeed(val id: String, val recurrenceRevision: Long)
    private data class HabitSeed(val id: String, val updatedAt: String)

    private class AwaitedResult : MethodChannel.Result {
        val completed = CountDownLatch(1)
        var value: Any? = null
        var errorCalled = false
        var notImplementedCalled = false

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
    private const val MarkerKeyword = "Search 集成共词"
    private const val AnniversaryTitle = "$MarkerKeyword Anniversary🎉"
    private const val QueryGeneration = 7L
    private const val AnniversaryCleanupPageSize = 200
    private const val MaxAnniversaryCleanupPages = 100
    private val TargetTypes = listOf("event", "habit", "anniversary")
}
