package com.excellentcalendar.excellent_calendar.bridge

import com.excellentcalendar.excellent_calendar.android.alarm.CancelResult
import com.excellentcalendar.excellent_calendar.android.alarm.ReminderScheduler
import com.excellentcalendar.excellent_calendar.android.alarm.ScheduleResult
import com.excellentcalendar.excellent_calendar.bridge.channel.NativeBridgeLogger
import com.excellentcalendar.excellent_calendar.bridge.channel.NativeMethodChannelHandler
import com.excellentcalendar.excellent_calendar.bridge.channel.ResultDispatcher
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderContract
import com.excellentcalendar.excellent_calendar.bridge.native.NativeEventBridge
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderNativeOrchestrator
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReminderMethodChannelHandlerTest {
    @Test
    fun createReminderSuccessSchedulesAndMarksScheduled() {
        val fakeBridge = FakeNativeEventBridge()
        val fakeScheduler = FakeReminderScheduler()

        val result = invoke(handler(fakeBridge, fakeScheduler), NativeMethodChannelHandler.MethodReminderCreate, createReminderArguments())
        val returned = result.successMap()

        assertEquals("reminder.create", NativeMethodChannelHandler.MethodReminderCreate)
        assertEquals("reminder-1", fakeScheduler.scheduledIds.single())
        assertEquals("reminder-1", fakeBridge.markScheduledIds.single())
        assertEquals(true, returned["ok"])
        assertEquals(1, returned["contract_version"])
        assertEquals("mark-scheduled-request", returned["request_id"])
        @Suppress("UNCHECKED_CAST")
        val data = returned["data"] as Map<String, Any?>
        assertEquals("scheduled", data["status"])
        assertFalse(result.errorCalled)
    }

    @Test
    fun createReminderNativeFailureDoesNotSchedule() {
        val nativeFailure = nativeResult(
            ok = false,
            data = null,
            error = error("REMINDER_TARGET_NOT_FOUND", "Reminder target does not exist"),
            requestId = "create-failed",
        )
        val fakeBridge = FakeNativeEventBridge(createReminderJson = NativeContractJsonCodec.encodeObject(nativeFailure))
        val fakeScheduler = FakeReminderScheduler()

        val result = invoke(handler(fakeBridge, fakeScheduler), NativeMethodChannelHandler.MethodReminderCreate, createReminderArguments())

        assertEquals(emptyList<String>(), fakeScheduler.scheduledIds)
        assertEquals("REMINDER_TARGET_NOT_FOUND", result.errorCode())
        assertEquals("create-failed", result.successMap()["request_id"])
    }

    @Test
    fun alarmScheduleFailureMarksReminderFailed() {
        val fakeBridge = FakeNativeEventBridge()
        val fakeScheduler = FakeReminderScheduler(
            scheduleResult = ScheduleResult.Failure(
                code = NativeErrorCodes.AlarmScheduleFailed,
                message = "Android alarm scheduling failed.",
                retryable = true,
            ),
        )

        val result = invoke(handler(fakeBridge, fakeScheduler), NativeMethodChannelHandler.MethodReminderCreate, createReminderArguments())
        @Suppress("UNCHECKED_CAST")
        val data = result.successMap()["data"] as Map<String, Any?>

        assertEquals("reminder-1", fakeBridge.markFailedCalls.single().first)
        assertEquals("Android alarm scheduling failed.", fakeBridge.markFailedCalls.single().second)
        assertEquals("failed", data["status"])
        assertEquals("mark-failed-request", result.successMap()["request_id"])
    }

    @Test
    fun unsupportedWechatMethodIsNotSilentlyIgnored() {
        val fakeBridge = FakeNativeEventBridge(
            createReminderJson = NativeContractJsonCodec.encodeObject(
                nativeResult(
                    ok = true,
                    data = reminderResponse(methods = listOf("wechat"), status = "pending"),
                    error = null,
                    requestId = "create-wechat",
                ),
            ),
        )
        val fakeScheduler = FakeReminderScheduler()

        val result = invoke(
            handler(fakeBridge, fakeScheduler),
            NativeMethodChannelHandler.MethodReminderCreate,
            createReminderArguments(methods = listOf("wechat")),
        )

        assertEquals("reminder-1", fakeScheduler.scheduledIds.single())
        assertEquals("reminder-1", fakeBridge.markFailedCalls.single().first)
        @Suppress("UNCHECKED_CAST")
        val data = result.successMap()["data"] as Map<String, Any?>
        assertEquals("failed", data["status"])
    }

    @Test
    fun cancelReminderSuccessCancelsAlarmThenNativeSoftDelete() {
        val fakeBridge = FakeNativeEventBridge()
        val fakeScheduler = FakeReminderScheduler()

        val result = invoke(handler(fakeBridge, fakeScheduler), NativeMethodChannelHandler.MethodReminderCancel, cancelReminderArguments())
        @Suppress("UNCHECKED_CAST")
        val data = result.successMap()["data"] as Map<String, Any?>

        assertEquals("reminder-1", fakeScheduler.cancelledIds.single())
        assertEquals("reminder-1", fakeBridge.cancelReminderIds.single())
        assertEquals("cancelled", data["status"])
        assertEquals(false, data["is_enabled"])
        assertEquals("2026-06-14T01:00:00Z", data["deleted_at"])
    }

    @Test
    fun cancelMissingReminderReturnsNotFoundWithoutCancellingAlarm() {
        val fakeBridge = FakeNativeEventBridge(
            listRemindersJson = NativeContractJsonCodec.encodeObject(
                nativeResult(
                    ok = true,
                    data = reminderListResponse(emptyList()),
                    error = null,
                    requestId = "list-empty",
                ),
            ),
        )
        val fakeScheduler = FakeReminderScheduler()

        val result = invoke(handler(fakeBridge, fakeScheduler), NativeMethodChannelHandler.MethodReminderCancel, cancelReminderArguments())

        assertEquals(emptyList<String>(), fakeScheduler.cancelledIds)
        assertEquals(NativeErrorCodes.ReminderNotFound, result.errorCode())
        assertEquals(emptyList<String>(), fakeBridge.cancelReminderIds)
    }

    @Test
    fun cancelAlarmFailureDoesNotSoftDeleteInNative() {
        val fakeBridge = FakeNativeEventBridge()
        val fakeScheduler = FakeReminderScheduler(
            cancelResult = CancelResult.Failure(
                code = NativeErrorCodes.AlarmCancelFailed,
                message = "Android alarm cancellation failed.",
                retryable = true,
            ),
        )

        val result = invoke(handler(fakeBridge, fakeScheduler), NativeMethodChannelHandler.MethodReminderCancel, cancelReminderArguments())

        assertEquals(NativeErrorCodes.AlarmCancelFailed, result.errorCode())
        assertEquals(emptyList<String>(), fakeBridge.cancelReminderIds)
    }

    @Test
    fun cancelNativePersistenceFailureReschedulesAsCompensation() {
        val nativeFailure = nativeResult(
            ok = false,
            data = null,
            error = error("STORAGE_IO_ERROR", "Storage input/output operation failed"),
            requestId = "cancel-storage-failed",
        )
        val fakeBridge = FakeNativeEventBridge(cancelReminderJson = NativeContractJsonCodec.encodeObject(nativeFailure))
        val fakeScheduler = FakeReminderScheduler()

        val result = invoke(handler(fakeBridge, fakeScheduler), NativeMethodChannelHandler.MethodReminderCancel, cancelReminderArguments())

        assertEquals(listOf("reminder-1"), fakeScheduler.cancelledIds)
        assertEquals(listOf("reminder-1"), fakeScheduler.scheduledIds)
        assertEquals("STORAGE_IO_ERROR", result.errorCode())
        assertEquals("cancel-storage-failed", result.successMap()["request_id"])
    }

    @Test
    fun repeatedCancelReturnsStableCancelledResult() {
        val alreadyCancelled = reminderResponse(
            status = "cancelled",
            isEnabled = false,
            deletedAt = "2026-06-14T01:00:00Z",
        )
        val fakeBridge = FakeNativeEventBridge(
            listRemindersJson = NativeContractJsonCodec.encodeObject(
                nativeResult(
                    ok = true,
                    data = reminderListResponse(listOf(alreadyCancelled)),
                    error = null,
                    requestId = "list-cancelled",
                ),
            ),
            cancelReminderJson = NativeContractJsonCodec.encodeObject(
                nativeResult(
                    ok = true,
                    data = alreadyCancelled,
                    error = null,
                    requestId = "cancel-again",
                ),
            ),
        )
        val fakeScheduler = FakeReminderScheduler()

        val result = invoke(handler(fakeBridge, fakeScheduler), NativeMethodChannelHandler.MethodReminderCancel, cancelReminderArguments())
        @Suppress("UNCHECKED_CAST")
        val data = result.successMap()["data"] as Map<String, Any?>

        assertEquals("reminder-1", fakeScheduler.cancelledIds.single())
        assertEquals(emptyList<String>(), fakeScheduler.scheduledIds)
        assertEquals("cancelled", data["status"])
        assertEquals("cancel-again", result.successMap()["request_id"])
    }

    @Test
    fun unknownReminderMethodIsNotImplemented() {
        val result = invoke(handler(FakeNativeEventBridge(), FakeReminderScheduler()), "reminder.delete", cancelReminderArguments())

        assertTrue(result.notImplementedCalled)
        assertFalse(result.successCalled)
        assertFalse(result.errorCalled)
    }

    private fun handler(
        fakeBridge: FakeNativeEventBridge,
        fakeScheduler: FakeReminderScheduler,
    ): NativeMethodChannelHandler {
        return NativeMethodChannelHandler(
            nativeEventBridge = fakeBridge,
            reminderOrchestrator = ReminderNativeOrchestrator(
                nativeBridge = fakeBridge,
                scheduler = fakeScheduler,
                logger = { _, _, _ -> },
            ),
            executor = Executor { command -> command.run() },
            resultDispatcher = ResultDispatcher { block -> block() },
            logger = NativeBridgeLogger { _, _, _ -> },
        )
    }

    private fun invoke(
        handler: NativeMethodChannelHandler,
        method: String,
        arguments: Map<String, Any?>,
    ): RecordingResult {
        val result = RecordingResult()
        handler.onMethodCall(MethodCall(method, arguments), result)
        return result
    }

    private fun createReminderArguments(
        methods: List<String> = listOf("popup", "ring"),
    ): Map<String, Any?> {
        return linkedMapOf(
            "target_type" to "event",
            "target_id" to "event-1",
            "remind_at" to "2026-06-15T01:00:00Z",
            "advance_minutes" to null,
            "methods" to methods,
            "message" to null,
            "is_enabled" to true,
            "source" to "manual",
        )
    }

    private fun cancelReminderArguments(): Map<String, Any?> {
        return linkedMapOf(
            "id" to "reminder-1",
            "reason" to "user_requested",
        )
    }

    private class FakeReminderScheduler(
        private val scheduleResult: ScheduleResult = ScheduleResult.Success,
        private val cancelResult: CancelResult = CancelResult.Success,
    ) : ReminderScheduler {
        val scheduledIds = mutableListOf<String>()
        val cancelledIds = mutableListOf<String>()

        override fun schedule(reminder: ReminderContract): ScheduleResult {
            scheduledIds.add(reminder.id)
            if ("wechat" in reminder.methods) {
                return ScheduleResult.Failure(
                    code = NativeErrorCodes.FeatureNotImplemented,
                    message = "Reminder method is not supported by Android local scheduler: wechat",
                    retryable = false,
                )
            }
            return scheduleResult
        }

        override fun cancel(reminderId: String): CancelResult {
            cancelledIds.add(reminderId)
            return cancelResult
        }
    }

    private class FakeNativeEventBridge(
        private val createReminderJson: String = NativeContractJsonCodec.encodeObject(
            nativeResult(ok = true, data = reminderResponse(status = "pending"), error = null, requestId = "create-reminder"),
        ),
        private val cancelReminderJson: String = NativeContractJsonCodec.encodeObject(
            nativeResult(
                ok = true,
                data = reminderResponse(status = "cancelled", isEnabled = false, deletedAt = "2026-06-14T01:00:00Z"),
                error = null,
                requestId = "cancel-reminder",
            ),
        ),
        private val listRemindersJson: String = NativeContractJsonCodec.encodeObject(
            nativeResult(
                ok = true,
                data = reminderListResponse(listOf(reminderResponse(status = "scheduled"))),
                error = null,
                requestId = "list-reminders",
            ),
        ),
    ) : NativeEventBridge {
        val markScheduledIds = mutableListOf<String>()
        val markFailedCalls = mutableListOf<Pair<String, String>>()
        val cancelReminderIds = mutableListOf<String>()

        override fun createReminder(requestJson: String): String = createReminderJson

        override fun cancelReminder(requestJson: String): String {
            val request = NativeContractJsonCodec.decodeObject(requestJson)
            cancelReminderIds.add(request["id"] as String)
            return cancelReminderJson
        }

        override fun listReminders(requestJson: String): String = listRemindersJson

        override fun markReminderScheduled(reminderId: String): String {
            markScheduledIds.add(reminderId)
            return NativeContractJsonCodec.encodeObject(
                nativeResult(
                    ok = true,
                    data = reminderResponse(status = "scheduled", scheduledAt = "2026-06-14T00:00:00Z"),
                    error = null,
                    requestId = "mark-scheduled-request",
                ),
            )
        }

        override fun markReminderFailed(reminderId: String, failureReason: String): String {
            markFailedCalls.add(reminderId to failureReason)
            return NativeContractJsonCodec.encodeObject(
                nativeResult(
                    ok = true,
                    data = reminderResponse(status = "failed", failureReason = failureReason),
                    error = null,
                    requestId = "mark-failed-request",
                ),
            )
        }

        override fun createEvent(requestJson: String): String = unsupported()

        override fun searchEvents(requestJson: String): String = unsupported()

        override fun completeEvent(requestJson: String): String = unsupported()

        override fun reopenEvent(requestJson: String): String = unsupported()

        private fun unsupported(): String {
            return NativeContractJsonCodec.encodeObject(
                nativeResult(
                    ok = false,
                    data = null,
                    error = error(NativeErrorCodes.FeatureNotImplemented, "Unsupported in reminder test"),
                    requestId = "unsupported",
                ),
            )
        }
    }

    private class RecordingResult : MethodChannel.Result {
        var successValue: Any? = null
            private set
        var successCalled = false
            private set
        var errorCalled = false
            private set
        var notImplementedCalled = false
            private set

        override fun success(result: Any?) {
            successCalled = true
            successValue = result
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            errorCalled = true
        }

        override fun notImplemented() {
            notImplementedCalled = true
        }

        fun successMap(): Map<String, Any?> {
            assertTrue(successCalled)
            @Suppress("UNCHECKED_CAST")
            return successValue as Map<String, Any?>
        }

        fun errorCode(): String {
            @Suppress("UNCHECKED_CAST")
            val error = successMap()["error"] as Map<String, Any?>
            return error["code"] as String
        }
    }

    companion object {
        private fun nativeResult(
            ok: Boolean,
            data: Any?,
            error: Map<String, Any?>?,
            requestId: String?,
        ): Map<String, Any?> {
            return linkedMapOf(
                "ok" to ok,
                "data" to data,
                "error" to error,
                "contract_version" to 1,
                "request_id" to requestId,
            )
        }

        private fun error(code: String, message: String): Map<String, Any?> {
            return linkedMapOf(
                "code" to code,
                "message" to message,
                "details" to null,
                "retryable" to false,
            )
        }

        private fun reminderListResponse(items: List<Map<String, Any?>>): Map<String, Any?> {
            return linkedMapOf(
                "items" to items,
                "pagination" to linkedMapOf(
                    "total" to items.size,
                    "page" to 1,
                    "page_size" to 200,
                    "has_more" to false,
                    "next_cursor" to null,
                ),
            )
        }

        private fun reminderResponse(
            methods: List<String> = listOf("popup", "ring"),
            status: String,
            isEnabled: Boolean = true,
            scheduledAt: String? = null,
            failureReason: String? = null,
            deletedAt: String? = null,
        ): Map<String, Any?> {
            return linkedMapOf(
                "id" to "reminder-1",
                "target_type" to "event",
                "target_id" to "event-1",
                "remind_at" to "2026-06-15T01:00:00Z",
                "methods" to methods,
                "advance_minutes" to null,
                "message" to null,
                "is_enabled" to isEnabled,
                "status" to status,
                "scheduled_at" to scheduledAt,
                "last_triggered_at" to null,
                "failure_reason" to failureReason,
                "created_at" to "2026-06-14T00:00:00Z",
                "updated_at" to "2026-06-14T00:00:00Z",
                "deleted_at" to deletedAt,
            )
        }
    }
}
