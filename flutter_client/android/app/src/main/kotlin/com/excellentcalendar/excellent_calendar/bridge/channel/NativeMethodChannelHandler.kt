package com.excellentcalendar.excellent_calendar.bridge.channel

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.excellentcalendar.excellent_calendar.bridge.auth.AuthTokenSecureStorage
import com.excellentcalendar.excellent_calendar.bridge.contract.CompleteEventRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.CancelReminderRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.CreateEventRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.CreateReminderRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.DeleteEventRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.EmptyRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.EventListResponseContract
import com.excellentcalendar.excellent_calendar.bridge.contract.EventResponseContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ListRemindersRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeContractViolation
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.OpenNotificationSettingsContract
import com.excellentcalendar.excellent_calendar.bridge.contract.RequestNotificationPermissionContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReopenEventRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReconcileReminderScheduleContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderListResponseContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderResponseContract
import com.excellentcalendar.excellent_calendar.bridge.contract.SearchEventRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.SchedulePendingRemindersContract
import com.excellentcalendar.excellent_calendar.bridge.contract.UpdateEventRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.UpdateReminderRequestContract
import com.excellentcalendar.excellent_calendar.bridge.native.NativeBridgeUnavailableException
import com.excellentcalendar.excellent_calendar.bridge.native.NativeCalendarCoreBridge
import com.excellentcalendar.excellent_calendar.bridge.notification.NotificationMethodOrchestrator
import com.excellentcalendar.excellent_calendar.bridge.reminder.PendingReminderScheduleService
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderNativeOrchestrator
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderScheduleCoordinator
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 结果派发器。
 *
 * Flutter 的 `MethodChannel.Result` 通常应在主线程回调。把“如何切回主线程”抽象成接口，
 * 可以让单元测试用同步实现，生产环境用 Android Handler。
 */
fun interface ResultDispatcher {
    fun dispatch(block: () -> Unit)
}

/**
 * native bridge 日志接口。
 *
 * 这里没有直接在业务代码里固定使用 `Log.d`，是为了测试时替换成空 logger 或断言 logger。
 */
fun interface NativeBridgeLogger {
    fun log(method: String, requestId: String?, message: String)
}

/** 使用 Android 主线程 Looper，把回调投递回 UI 线程。 */
class MainThreadResultDispatcher : ResultDispatcher {
    private val handler = Handler(Looper.getMainLooper())

    override fun dispatch(block: () -> Unit) {
        handler.post(block)
    }
}

/** 生产环境 logger：把方法名、request_id 和状态写入 Logcat。 */
class AndroidNativeBridgeLogger : NativeBridgeLogger {
    override fun log(method: String, requestId: String?, message: String) {
        Log.d(NativeMethodChannelHandler.LogTag, "method=$method request_id=${requestId ?: "null"} $message")
    }
}

/**
 * Flutter MethodChannel 的统一入口。
 *
 * 调用链：
 * Dart -> MethodChannel -> `onMethodCall` -> Kotlin 合约校验 -> `NativeCalendarCoreBridge`
 * -> JNI/C++ -> NativeResult JSON -> Kotlin 校验响应 -> Map 返回 Dart。
 *
 * 这里实现 `AutoCloseable`，说明它持有需要释放的资源：默认的单线程 executor。
 */
class NativeMethodChannelHandler(
    private val nativeCalendarCoreBridge: NativeCalendarCoreBridge,
    private val authTokenSecureStorage: AuthTokenSecureStorage? = null,
    private val reminderOrchestrator: ReminderNativeOrchestrator? = null,
    private val notificationOrchestrator: NotificationMethodOrchestrator? = null,
    private val pendingReminderScheduleService: PendingReminderScheduleService? = null,
    private val reminderScheduleCoordinator: ReminderScheduleCoordinator? = null,
    /**
     * native 调用放到后台 executor 中执行，避免阻塞 Android 主线程。
     *
     * 默认是单线程 executor：这让 native 调用按顺序执行，能降低 JSON 文件仓库并发写入复杂度。
     */
    private val executor: Executor = Executors.newSingleThreadExecutor(),
    private val resultDispatcher: ResultDispatcher = MainThreadResultDispatcher(),
    private val logger: NativeBridgeLogger = AndroidNativeBridgeLogger(),
) : MethodChannel.MethodCallHandler, AutoCloseable {
    /** Flutter 每次通过 MethodChannel 调用方法时，都会进入这里。 */
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val completion = SingleCompletion(result, resultDispatcher)
        when (call.method) {
            MethodEventCreate -> handleCreateEvent(call, completion)
            MethodEventUpdate -> handleUpdateEvent(call, completion)
            MethodEventDelete -> handleDeleteEvent(call, completion)
            MethodEventSearch -> handleSearchEvents(call, completion)
            MethodEventComplete -> handleCompleteEvent(call, completion)
            MethodEventReopen -> handleReopenEvent(call, completion)
            MethodReminderCreate -> handleCreateReminder(call, completion)
            MethodReminderUpdate -> handleUpdateReminder(call, completion)
            MethodReminderCancel -> handleCancelReminder(call, completion)
            MethodReminderList -> handleListReminders(call, completion)
            MethodReminderSchedulePending -> handleSchedulePending(call, completion)
            MethodReminderReconcileSchedule -> handleReconcileSchedule(call, completion)
            MethodNotificationInitialize -> handleNotificationInitialize(call, completion)
            MethodNotificationPermissionStatus -> handleNotificationPermissionStatus(call, completion)
            MethodNotificationRequestPermission -> handleNotificationRequestPermission(call, completion)
            MethodNotificationOpenSettings -> handleNotificationOpenSettings(call, completion)
            MethodNotificationGetInitialTapPayload -> handleGetInitialTapPayload(call, completion)
            MethodAuthRefreshTokenStore -> handleAuthRefreshTokenStore(call, completion)
            MethodAuthRefreshTokenRead -> handleAuthRefreshTokenRead(call, completion)
            MethodAuthRefreshTokenDelete -> handleAuthRefreshTokenDelete(call, completion)
            MethodAuthRefreshTokenExists -> handleAuthRefreshTokenExists(call, completion)
            else -> completion.notImplemented()
        }
    }

    /** 释放后台线程池。Activity 销毁时会调用，避免线程泄漏。 */
    override fun close() {
        if (executor is ExecutorService) {
            executor.shutdownNow()
        }
        notificationOrchestrator?.close()
    }

    /** 解析并校验创建事件请求，然后交给 native bridge。 */
    private fun handleCreateEvent(call: MethodCall, completion: SingleCompletion) {
        val request = try {
            CreateEventRequestContract.fromMethodArguments(call.arguments)
        } catch (error: NativeContractViolation) {
            completion.success(contractFailure(call.method, error).toMap())
            return
        }
        executeNative(call.method, completion, EventResponseContract::validate) {
            nativeCalendarCoreBridge.createEvent(request.toJson())
        }
    }

    /** 解析并校验搜索请求，然后交给 native bridge。 */
    private fun handleUpdateEvent(call: MethodCall, completion: SingleCompletion) {
        val request = try {
            UpdateEventRequestContract.fromMethodArguments(call.arguments)
        } catch (error: NativeContractViolation) {
            completion.success(contractFailure(call.method, error).toMap())
            return
        }
        executeNative(call.method, completion, EventResponseContract::validate) {
            nativeCalendarCoreBridge.updateEvent(request.toJson())
        }
    }

    private fun handleDeleteEvent(call: MethodCall, completion: SingleCompletion) {
        val request = try {
            DeleteEventRequestContract.fromMethodArguments(call.arguments)
        } catch (error: NativeContractViolation) {
            completion.success(contractFailure(call.method, error).toMap())
            return
        }
        executeNative(call.method, completion, EventResponseContract::validate) {
            nativeCalendarCoreBridge.deleteEvent(request.toJson())
        }
    }

    private fun handleSearchEvents(call: MethodCall, completion: SingleCompletion) {
        val request = try {
            SearchEventRequestContract.fromMethodArguments(call.arguments)
        } catch (error: NativeContractViolation) {
            completion.success(contractFailure(call.method, error).toMap())
            return
        }
        executeNative(call.method, completion, EventListResponseContract::validate) {
            nativeCalendarCoreBridge.searchEvents(request.toJson())
        }
    }

    /** 解析完成单次事件请求，并将 C++ NativeResult 完整返回给 Flutter。 */
    private fun handleCompleteEvent(call: MethodCall, completion: SingleCompletion) {
        val request = try {
            CompleteEventRequestContract.fromMethodArguments(call.arguments)
        } catch (error: NativeContractViolation) {
            completion.success(contractFailure(call.method, error).toMap())
            return
        }
        executeNative(call.method, completion, EventResponseContract::validate) {
            nativeCalendarCoreBridge.completeEvent(request.toJson())
        }
    }

    /** 解析“重新打开事件实例”请求。 */
    private fun handleReopenEvent(call: MethodCall, completion: SingleCompletion) {
        val request = try {
            ReopenEventRequestContract.fromMethodArguments(call.arguments)
        } catch (error: NativeContractViolation) {
            completion.success(contractFailure(call.method, error).toMap())
            return
        }
        executeNative(call.method, completion, EventResponseContract::validate) {
            nativeCalendarCoreBridge.reopenEvent(request.toJson())
        }
    }

    private fun handleCreateReminder(call: MethodCall, completion: SingleCompletion) {
        val request = try {
            CreateReminderRequestContract.fromMethodArguments(call.arguments)
        } catch (error: NativeContractViolation) {
            completion.success(contractFailure(call.method, error).toMap())
            return
        }
        executeReminder(call.method, completion) {
            requireReminderOrchestrator(call.method).createReminder(request.toJson())
        }
    }

    private fun handleUpdateReminder(call: MethodCall, completion: SingleCompletion) {
        val request = try {
            UpdateReminderRequestContract.fromMethodArguments(call.arguments)
        } catch (error: NativeContractViolation) {
            completion.success(contractFailure(call.method, error).toMap())
            return
        }
        executeReminder(call.method, completion) {
            requireReminderOrchestrator(call.method).updateReminder(request.toJson())
        }
    }

    private fun handleCancelReminder(call: MethodCall, completion: SingleCompletion) {
        val request = try {
            CancelReminderRequestContract.fromMethodArguments(call.arguments)
        } catch (error: NativeContractViolation) {
            completion.success(contractFailure(call.method, error).toMap())
            return
        }
        executeReminder(call.method, completion) {
            requireReminderOrchestrator(call.method).cancelReminder(request.toJson(), request.id)
        }
    }

    private fun handleListReminders(call: MethodCall, completion: SingleCompletion) {
        val request = try {
            ListRemindersRequestContract.fromMethodArguments(call.arguments)
        } catch (error: NativeContractViolation) {
            completion.success(contractFailure(call.method, error).toMap())
            return
        }
        executeNative(call.method, completion, ReminderListResponseContract::validate) {
            nativeCalendarCoreBridge.listReminders(request.toJson())
        }
    }

    private fun handleSchedulePending(call: MethodCall, completion: SingleCompletion) {
        val request = try {
            SchedulePendingRemindersContract.fromMethodArguments(call.arguments)
        } catch (error: NativeContractViolation) {
            completion.success(contractFailure(call.method, error).toMap())
            return
        }
        executeReminder(call.method, completion) {
            val coordinator = reminderScheduleCoordinator
            if (coordinator == null) {
                requirePendingScheduleService(call.method).schedulePending(request)
            } else {
                val reconciled = coordinator.reconcile(
                    ReconcileReminderScheduleContract(
                        com.excellentcalendar.excellent_calendar.bridge.contract.ReminderScheduleTrigger.AppStart,
                        force = request.forceReschedule,
                    ),
                )
                if (!reconciled.ok) {
                    reconciled
                } else {
                    @Suppress("UNCHECKED_CAST")
                    val data = reconciled.data as Map<String, Any?>
                    NativeResultContract.success(
                        linkedMapOf(
                            "scheduled_count" to if (data["action"] == "scheduled") 1 else 0,
                            "skipped_count" to 0,
                            "failed_count" to data["failed_count"],
                            "unsupported_method_count" to 0,
                            "has_more" to data["continuation_enqueued"],
                            "failed_reminder_ids" to data["failed_reminder_ids"],
                            "unsupported_reminder_ids" to emptyList<String>(),
                        ),
                    )
                }
            }
        }
    }

    private fun handleReconcileSchedule(call: MethodCall, completion: SingleCompletion) {
        val request = try {
            ReconcileReminderScheduleContract.fromMethodArguments(call.arguments)
        } catch (error: NativeContractViolation) {
            completion.success(contractFailure(call.method, error).toMap())
            return
        }
        executeReminder(call.method, completion) {
            requireReminderScheduleCoordinator(call.method).reconcile(request)
        }
    }

    private fun handleNotificationInitialize(call: MethodCall, completion: SingleCompletion) {
        if (!validateEmptyRequest(call, completion)) return
        executeLocal(call.method, completion) { requireNotificationOrchestrator(call.method).initialize() }
    }

    private fun handleNotificationPermissionStatus(call: MethodCall, completion: SingleCompletion) {
        if (!validateEmptyRequest(call, completion)) return
        executeLocal(call.method, completion) {
            requireNotificationOrchestrator(call.method).permissionStatus()
        }
    }

    private fun handleNotificationRequestPermission(call: MethodCall, completion: SingleCompletion) {
        val request = try {
            RequestNotificationPermissionContract.fromMethodArguments(call.arguments)
        } catch (error: NativeContractViolation) {
            completion.success(contractFailure(call.method, error).toMap())
            return
        }
        try {
            requireNotificationOrchestrator(call.method).requestPermission(request) { nativeResult ->
                logger.log(call.method, nativeResult.requestId, "completed ok=${nativeResult.ok}")
                completion.success(nativeResult.toMap())
            }
        } catch (error: Throwable) {
            completion.success(nativeInternalFailure(call.method, error).toMap())
        }
    }

    private fun handleNotificationOpenSettings(call: MethodCall, completion: SingleCompletion) {
        val request = try {
            OpenNotificationSettingsContract.fromMethodArguments(call.arguments)
        } catch (error: NativeContractViolation) {
            completion.success(contractFailure(call.method, error).toMap())
            return
        }
        executeLocal(call.method, completion) {
            requireNotificationOrchestrator(call.method).openSettings(request.settingsTarget)
        }
    }

    private fun handleGetInitialTapPayload(call: MethodCall, completion: SingleCompletion) {
        if (!validateEmptyRequest(call, completion)) return
        executeLocal(call.method, completion) {
            requireNotificationOrchestrator(call.method).takeInitialTapPayload()
        }
    }

    private fun validateEmptyRequest(call: MethodCall, completion: SingleCompletion): Boolean {
        return try {
            EmptyRequestContract.validate(call.arguments)
            true
        } catch (error: NativeContractViolation) {
            completion.success(contractFailure(call.method, error).toMap())
            false
        }
    }

    private fun executeLocal(
        method: String,
        completion: SingleCompletion,
        operation: () -> NativeResultContract,
    ) {
        val nativeResult = try {
            operation()
        } catch (error: NativeContractViolation) {
            contractFailure(method, error)
        } catch (error: Throwable) {
            nativeInternalFailure(method, error)
        }
        logger.log(method, nativeResult.requestId, "completed ok=${nativeResult.ok}")
        completion.success(nativeResult.toMap())
    }

    /**
     * 执行一次 native 调用的通用模板。
     *
     * `dataValidator: (Any?) -> Unit` 是函数类型参数，表示调用方传入一个“校验 data 的函数”。
     * `nativeCall: () -> String` 也是函数类型参数，表示真正调用 C++ 并返回 JSON 的动作。
     */
    private fun executeNative(
        method: String,
        completion: SingleCompletion,
        dataValidator: (Any?) -> Unit,
        nativeCall: () -> String,
    ) {
        executor.execute {
            val nativeResult = try {
                val nativeJson = nativeCall()
                NativeResultContract.fromJson(nativeJson, dataValidator)
            } catch (error: NativeContractViolation) {
                contractFailure(method, error)
            } catch (error: NativeBridgeUnavailableException) {
                nativeUnavailableFailure(method, error)
            } catch (error: UnsatisfiedLinkError) {
                nativeUnavailableFailure(method, error)
            } catch (error: Throwable) {
                nativeInternalFailure(method, error)
            }
            logger.log(method, nativeResult.requestId, "completed ok=${nativeResult.ok}")
            completion.success(nativeResult.toMap())
        }
    }

    private fun executeReminder(
        method: String,
        completion: SingleCompletion,
        operation: () -> NativeResultContract,
    ) {
        executor.execute {
            val nativeResult = try {
                operation()
            } catch (error: NativeContractViolation) {
                contractFailure(method, error)
            } catch (error: NativeBridgeUnavailableException) {
                nativeUnavailableFailure(method, error)
            } catch (error: UnsatisfiedLinkError) {
                nativeUnavailableFailure(method, error)
            } catch (error: Throwable) {
                nativeInternalFailure(method, error)
            }
            logger.log(method, nativeResult.requestId, "completed ok=${nativeResult.ok}")
            completion.success(nativeResult.toMap())
        }
    }

    private fun requireReminderOrchestrator(method: String): ReminderNativeOrchestrator {
        return reminderOrchestrator ?: throw NativeBridgeUnavailableException(
            "Reminder orchestration is not configured for $method.",
        )
    }

    private fun requireNotificationOrchestrator(method: String): NotificationMethodOrchestrator {
        return notificationOrchestrator ?: throw NativeBridgeUnavailableException(
            "Notification orchestration is not configured for $method.",
        )
    }

    private fun requirePendingScheduleService(method: String): PendingReminderScheduleService {
        return pendingReminderScheduleService ?: throw NativeBridgeUnavailableException(
            "Pending reminder scheduling is not configured for $method.",
        )
    }

    private fun requireReminderScheduleCoordinator(method: String): ReminderScheduleCoordinator {
        return reminderScheduleCoordinator ?: throw NativeBridgeUnavailableException(
            "Reminder schedule coordinator is not configured for $method.",
        )
    }

    /** 把 Kotlin 侧或 native 响应侧的合约错误转换成统一 NativeResult。 */
    private fun contractFailure(method: String, error: NativeContractViolation): NativeResultContract {
        logger.log(method, null, "contract validation failed field=${error.field ?: "unknown"}")
        return NativeResultContract.failure(
            code = NativeErrorCodes.ContractValidationFailed,
            message = error.message ?: "Request or native response does not match contract.",
            details = linkedMapOf(
                "method" to method,
                "field" to error.field,
            ),
        )
    }

    /** native 库不可用、JNI 符号缺失等基础设施问题的错误包装。 */
    private fun nativeUnavailableFailure(method: String, error: Throwable): NativeResultContract {
        logger.log(method, null, "native unavailable type=${error.javaClass.simpleName}")
        return NativeResultContract.failure(
            code = NativeErrorCodes.NativeInternalError,
            message = "Native calendar core bridge is unavailable.",
            details = linkedMapOf(
                "method" to method,
                "reason" to (error.message ?: error.javaClass.simpleName),
            ),
        )
    }

    /** 兜底捕获未知异常，避免异常穿透到 Flutter engine 导致调用悬挂。 */
    private fun nativeInternalFailure(method: String, error: Throwable): NativeResultContract {
        logger.log(method, null, "native call failed type=${error.javaClass.simpleName}")
        return NativeResultContract.failure(
            code = NativeErrorCodes.NativeInternalError,
            message = "Native calendar core bridge call failed.",
            details = linkedMapOf(
                "method" to method,
                "reason" to error.javaClass.simpleName,
            ),
        )
    }

    /**
     * 保证一次 MethodChannel 调用最多完成一次。
     *
     * `AtomicBoolean.compareAndSet(false, true)` 是线程安全的“只允许第一个人成功”的写法。
     * 这可以防止异常路径、超时路径或重复回调导致 Flutter 收到多次 result。
     */
    private class SingleCompletion(
        private val result: MethodChannel.Result,
        private val dispatcher: ResultDispatcher,
    ) {
        private val completed = AtomicBoolean(false)

        fun success(value: Any?) {
            complete { result.success(value) }
        }

        fun notImplemented() {
            complete { result.notImplemented() }
        }

        private fun complete(block: () -> Unit) {
            if (completed.compareAndSet(false, true)) {
                dispatcher.dispatch(block)
            }
        }
    }

    // ---------------------------------------------------------------
    // Auth Refresh Token handlers
    // ---------------------------------------------------------------

    private fun handleAuthRefreshTokenStore(call: MethodCall, completion: SingleCompletion) {
        executor.execute {
            val storage = requireAuthStorage(call.method)
            try {
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as? Map<String, Any?>
                    ?: throw IllegalArgumentException("Arguments must be a Map")

                val refreshToken = args["refresh_token"] as? String
                    ?: throw IllegalArgumentException("Missing required field: refresh_token")
                val sessionId = args["session_id"] as? String
                    ?: throw IllegalArgumentException("Missing required field: session_id")
                val expiresAt = args["expires_at"] as? String
                    ?: throw IllegalArgumentException("Missing required field: expires_at")

                val ok = storage.store(refreshToken, sessionId, expiresAt)
                val nativeResult = if (ok) {
                    NativeResultContract.success(linkedMapOf("performed" to true, "message" to null))
                } else {
                    NativeResultContract.failure(
                        code = NativeErrorCodes.NativeInternalError,
                        message = "Failed to store refresh token.",
                    )
                }
                completion.success(nativeResult.toMap())
            } catch (e: Exception) {
                completion.success(nativeInternalFailure(call.method, e).toMap())
            }
        }
    }

    private fun handleAuthRefreshTokenRead(call: MethodCall, completion: SingleCompletion) {
        executor.execute {
            val storage = requireAuthStorage(call.method)
            try {
                val record = storage.read()
                if (record != null) {
                    val nativeResult = NativeResultContract.success(record)
                    completion.success(nativeResult.toMap())
                } else {
                    val nativeResult = NativeResultContract.failure(
                        code = NativeErrorCodes.NativeInternalError,
                        message = "No Refresh Token record exists.",
                    )
                    completion.success(nativeResult.toMap())
                }
            } catch (e: Exception) {
                completion.success(nativeInternalFailure(call.method, e).toMap())
            }
        }
    }

    private fun handleAuthRefreshTokenDelete(call: MethodCall, completion: SingleCompletion) {
        executor.execute {
            val storage = requireAuthStorage(call.method)
            try {
                val ok = storage.delete()
                val nativeResult = if (ok) {
                    NativeResultContract.success(linkedMapOf("performed" to true, "message" to null))
                } else {
                    NativeResultContract.failure(
                        code = NativeErrorCodes.NativeInternalError,
                        message = "Failed to delete refresh token.",
                    )
                }
                completion.success(nativeResult.toMap())
            } catch (e: Exception) {
                completion.success(nativeInternalFailure(call.method, e).toMap())
            }
        }
    }

    private fun handleAuthRefreshTokenExists(call: MethodCall, completion: SingleCompletion) {
        executor.execute {
            val storage = requireAuthStorage(call.method)
            try {
                val exists = storage.exists()
                val nativeResult = NativeResultContract.success(linkedMapOf("exists" to exists))
                completion.success(nativeResult.toMap())
            } catch (e: Exception) {
                completion.success(nativeInternalFailure(call.method, e).toMap())
            }
        }
    }

    private fun requireAuthStorage(method: String): AuthTokenSecureStorage {
        return authTokenSecureStorage ?: throw NativeBridgeUnavailableException(
            "Auth token secure storage is not configured for $method.",
        )
    }

    companion object {
        /** Dart 和 Kotlin 必须使用完全相同的 channel 名称才能通信。 */
        const val ChannelName = "excellent_calendar/native"
        /** 以下方法名是 Dart 调用 native 能力时使用的字符串协议。 */
        const val MethodEventCreate = "event.create"
        const val MethodEventUpdate = "event.update"
        const val MethodEventDelete = "event.delete"
        const val MethodEventSearch = "event.search"
        const val MethodEventComplete = "event.complete"
        const val MethodEventReopen = "event.reopen"
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
        const val LogTag = "ExcellentCalendarNative"

        const val MethodAuthRefreshTokenStore = "auth.refresh_token.store"
        const val MethodAuthRefreshTokenRead = "auth.refresh_token.read"
        const val MethodAuthRefreshTokenDelete = "auth.refresh_token.delete"
        const val MethodAuthRefreshTokenExists = "auth.refresh_token.exists"
    }
}
