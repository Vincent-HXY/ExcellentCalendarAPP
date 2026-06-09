package com.excellentcalendar.excellent_calendar.bridge.channel

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.excellentcalendar.excellent_calendar.bridge.contract.CompleteEventRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.CreateEventRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.EventListResponseContract
import com.excellentcalendar.excellent_calendar.bridge.contract.EventOccurrenceStateResponseContract
import com.excellentcalendar.excellent_calendar.bridge.contract.EventResponseContract
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeContractViolation
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReopenEventRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.SearchEventRequestContract
import com.excellentcalendar.excellent_calendar.bridge.native.NativeBridgeUnavailableException
import com.excellentcalendar.excellent_calendar.bridge.native.NativeEventBridge
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
 * Dart -> MethodChannel -> `onMethodCall` -> Kotlin 合约校验 -> `NativeEventBridge`
 * -> JNI/C++ -> NativeResult JSON -> Kotlin 校验响应 -> Map 返回 Dart。
 *
 * 这里实现 `AutoCloseable`，说明它持有需要释放的资源：默认的单线程 executor。
 */
class NativeMethodChannelHandler(
    private val nativeEventBridge: NativeEventBridge,
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
            MethodEventSearch -> handleSearchEvents(call, completion)
            MethodEventComplete -> handleCompleteEvent(call, completion)
            MethodEventReopen -> handleReopenEvent(call, completion)
            else -> completion.notImplemented()
        }
    }

    /** 释放后台线程池。Activity 销毁时会调用，避免线程泄漏。 */
    override fun close() {
        if (executor is ExecutorService) {
            executor.shutdownNow()
        }
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
            nativeEventBridge.createEvent(request.toJson())
        }
    }

    /** 解析并校验搜索请求，然后交给 native bridge。 */
    private fun handleSearchEvents(call: MethodCall, completion: SingleCompletion) {
        val request = try {
            SearchEventRequestContract.fromMethodArguments(call.arguments)
        } catch (error: NativeContractViolation) {
            completion.success(contractFailure(call.method, error).toMap())
            return
        }
        executeNative(call.method, completion, EventListResponseContract::validate) {
            nativeEventBridge.searchEvents(request.toJson())
        }
    }

    /** 解析“完成事件实例”请求。当前 C++ 层未实现时，也会按 NativeResult 返回失败。 */
    private fun handleCompleteEvent(call: MethodCall, completion: SingleCompletion) {
        val request = try {
            CompleteEventRequestContract.fromMethodArguments(call.arguments)
        } catch (error: NativeContractViolation) {
            completion.success(contractFailure(call.method, error).toMap())
            return
        }
        executeNative(call.method, completion, EventOccurrenceStateResponseContract::validate) {
            nativeEventBridge.completeEvent(request.toJson())
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
        executeNative(call.method, completion, EventOccurrenceStateResponseContract::validate) {
            nativeEventBridge.reopenEvent(request.toJson())
        }
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
            message = "Native event bridge is unavailable.",
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
            message = "Native event bridge call failed.",
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

    companion object {
        /** Dart 和 Kotlin 必须使用完全相同的 channel 名称才能通信。 */
        const val ChannelName = "excellent_calendar/native"
        /** 以下方法名是 Dart 调用 native 能力时使用的字符串协议。 */
        const val MethodEventCreate = "event.create"
        const val MethodEventSearch = "event.search"
        const val MethodEventComplete = "event.complete"
        const val MethodEventReopen = "event.reopen"
        const val LogTag = "ExcellentCalendarNative"
    }
}
