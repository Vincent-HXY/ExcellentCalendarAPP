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
import com.excellentcalendar.excellent_calendar.bridge.native.NativeCalendarCoreBridge
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
    // 目的：验证提醒创建成功后会注册 Android 调度并回写 scheduled。
    // 方法：Fake Bridge/Scheduler 记录调用顺序，最终检查状态和 scheduledAt。
    @Test
    fun createReminderSuccessSchedulesAndMarksScheduled() {
        val fakeBridge = FakeNativeCalendarCoreBridge()
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

    // 目的：C++ 创建失败时不得注册闹钟；方法：Fake 返回业务失败并检查 Scheduler 未调用。
    @Test
    fun createReminderNativeFailureDoesNotSchedule() {
        val nativeFailure = nativeResult(
            ok = false,
            data = null,
            error = error("REMINDER_TARGET_NOT_FOUND", "Reminder target does not exist"),
            requestId = "create-failed",
        )
        val fakeBridge = FakeNativeCalendarCoreBridge(createReminderJson = NativeContractJsonCodec.encodeObject(nativeFailure))
        val fakeScheduler = FakeReminderScheduler()

        val result = invoke(handler(fakeBridge, fakeScheduler), NativeMethodChannelHandler.MethodReminderCreate, createReminderArguments())

        assertEquals(emptyList<String>(), fakeScheduler.scheduledIds)
        assertEquals("REMINDER_TARGET_NOT_FOUND", result.errorCode())
        assertEquals("create-failed", result.successMap()["request_id"])
    }

    // 目的：Android 调度失败后必须回写 failed；方法：Scheduler 返回失败并检查 markReminderFailed。
    @Test
    fun alarmScheduleFailureMarksReminderFailed() {
        val fakeBridge = FakeNativeCalendarCoreBridge()
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

    // 目的：当前不支持的微信提醒不能被静默忽略；方法：提交 wechat method 并检查明确错误。
    @Test
    fun unsupportedWechatMethodIsNotSilentlyIgnored() {
        val fakeBridge = FakeNativeCalendarCoreBridge(
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

    // 目的：验证取消顺序是先撤销系统闹钟，再在 C++ 中软删除。
    // 方法：Fake 记录两个边界调用并检查最终 cancelled 响应。
    @Test
    fun cancelReminderSuccessCancelsAlarmThenNativeSoftDelete() {
        val fakeBridge = FakeNativeCalendarCoreBridge()
        val fakeScheduler = FakeReminderScheduler()

        val result = invoke(handler(fakeBridge, fakeScheduler), NativeMethodChannelHandler.MethodReminderCancel, cancelReminderArguments())
        @Suppress("UNCHECKED_CAST")
        val data = result.successMap()["data"] as Map<String, Any?>

        assertEquals("reminder-1", fakeScheduler.cancelledIds.single())
        assertEquals("reminder-1", fakeBridge.cancelReminderIds.single())
        assertEquals("cancelled", data["status"])
        assertEquals(false, data["is_enabled"])
        assertEquals("user_cancelled", data["cancellation_reason"])
        assertEquals("2026-06-14T01:00:00Z", data["deleted_at"])
    }

    // 目的：不存在的 Reminder 不应触碰系统 Alarm；方法：预查询返回空列表并检查未调用 cancel。
    @Test
    fun cancelMissingReminderReturnsNotFoundWithoutCancellingAlarm() {
        val fakeBridge = FakeNativeCalendarCoreBridge(
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

    // 目的：系统闹钟取消失败时不得继续软删除；方法：Scheduler 返回失败并检查 C++ cancel 未调用。
    @Test
    fun cancelAlarmFailureDoesNotSoftDeleteInNative() {
        val fakeBridge = FakeNativeCalendarCoreBridge()
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

    // 目的：闹钟已取消但 C++ 持久化失败时执行补偿，避免活跃 Reminder 永久失去调度。
    // 方法：让 native cancel 失败，再检查 Scheduler 收到重新注册调用。
    @Test
    fun cancelNativePersistenceFailureReschedulesAsCompensation() {
        val nativeFailure = nativeResult(
            ok = false,
            data = null,
            error = error("STORAGE_IO_ERROR", "Storage input/output operation failed"),
            requestId = "cancel-storage-failed",
        )
        val fakeBridge = FakeNativeCalendarCoreBridge(cancelReminderJson = NativeContractJsonCodec.encodeObject(nativeFailure))
        val fakeScheduler = FakeReminderScheduler()

        val result = invoke(handler(fakeBridge, fakeScheduler), NativeMethodChannelHandler.MethodReminderCancel, cancelReminderArguments())

        assertEquals(listOf("reminder-1"), fakeScheduler.cancelledIds)
        assertEquals(listOf("reminder-1"), fakeScheduler.scheduledIds)
        assertEquals("STORAGE_IO_ERROR", result.errorCode())
        assertEquals("cancel-storage-failed", result.successMap()["request_id"])
    }

    // 目的：重复取消保持幂等结果；方法：连续调用两次并检查第二次仍稳定返回 cancelled。
    @Test
    fun repeatedCancelReturnsStableCancelledResult() {
        val alreadyCancelled = reminderResponse(
            status = "cancelled",
            isEnabled = false,
            cancellationReason = "user_cancelled",
            deletedAt = "2026-06-14T01:00:00Z",
        )
        val fakeBridge = FakeNativeCalendarCoreBridge(
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

    // 目的：未知 reminder 方法必须返回 notImplemented；方法：发送不存在的方法并检查结果探针。
    @Test
    fun unknownReminderMethodIsNotImplemented() {
        val result = invoke(handler(FakeNativeCalendarCoreBridge(), FakeReminderScheduler()), "reminder.delete", cancelReminderArguments())

        assertTrue(result.notImplementedCalled)
        assertFalse(result.successCalled)
        assertFalse(result.errorCalled)
    }

    // 组装被测 Handler，并注入 Fake JNI Bridge 与 Fake Android Scheduler。
    private fun handler(
        fakeBridge: FakeNativeCalendarCoreBridge,
        fakeScheduler: FakeReminderScheduler,
    ): NativeMethodChannelHandler {
        return NativeMethodChannelHandler(
            nativeCalendarCoreBridge = fakeBridge,
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

    // 模拟一次来自 Flutter 的 MethodCall，收集同步返回结果供断言。
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

    // Android 调度器替身：可配置成功/失败，并记录 schedule、cancel 的参数与次数。
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

    // C++ JNI 边界替身：为不同状态 API 返回预设 JSON，同时记录发生过的回写。
    private class FakeNativeCalendarCoreBridge(
        private val createReminderJson: String = NativeContractJsonCodec.encodeObject(
            nativeResult(ok = true, data = reminderResponse(status = "pending"), error = null, requestId = "create-reminder"),
        ),
        private val cancelReminderJson: String = NativeContractJsonCodec.encodeObject(
            nativeResult(
                ok = true,
                data = reminderResponse(
                    status = "cancelled",
                    isEnabled = false,
                    cancellationReason = "user_cancelled",
                    deletedAt = "2026-06-14T01:00:00Z",
                ),
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
    ) : NativeCalendarCoreBridge {
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

        override fun getReminder(requestJson: String): String = unsupported()

        override fun listSchedulableReminders(requestJson: String): String = unsupported()

        override fun markReminderScheduled(requestJson: String): String {
            val request = NativeContractJsonCodec.decodeObject(requestJson)
            markScheduledIds.add(request["id"] as String)
            return NativeContractJsonCodec.encodeObject(
                nativeResult(
                    ok = true,
                    data = reminderResponse(status = "scheduled", scheduledAt = "2026-06-14T00:00:00Z"),
                    error = null,
                    requestId = "mark-scheduled-request",
                ),
            )
        }

        override fun markReminderFailed(requestJson: String): String {
            val request = NativeContractJsonCodec.decodeObject(requestJson)
            val reminderId = request["id"] as String
            val failureReason = request["failure_reason"] as String
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

        override fun updateEvent(requestJson: String): String = unsupported()

        override fun deleteEvent(requestJson: String): String = unsupported()

        override fun searchEvents(requestJson: String): String = unsupported()

        override fun completeEvent(requestJson: String): String = unsupported()

        override fun reopenEvent(requestJson: String): String = unsupported()

        override fun updateReminder(requestJson: String): String = unsupported()

        override fun markReminderSent(requestJson: String): String = unsupported()

        override fun enableReminder(requestJson: String): String = unsupported()

        override fun disableReminder(requestJson: String): String = unsupported()

        override fun createNotification(requestJson: String): String = unsupported()

        override fun consumeReminderAfterDelivery(requestJson: String): String = unsupported()

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

    // MethodChannel 返回值探针，用于检查 success/error/notImplemented，而不启动 Flutter 引擎。
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
            cancellationReason: String? = null,
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
                "cancellation_reason" to cancellationReason,
                "created_at" to "2026-06-14T00:00:00Z",
                "updated_at" to "2026-06-14T00:00:00Z",
                "deleted_at" to deletedAt,
            )
        }
    }
}
