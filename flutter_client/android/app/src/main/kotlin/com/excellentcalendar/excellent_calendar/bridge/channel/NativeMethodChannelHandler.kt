package com.excellentcalendar.excellent_calendar.bridge.channel

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.excellentcalendar.excellent_calendar.bridge.contract.CreateEventRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.EventListResponseContract
import com.excellentcalendar.excellent_calendar.bridge.contract.EventResponseContract
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeContractViolation
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.SearchEventRequestContract
import com.excellentcalendar.excellent_calendar.bridge.native.NativeBridgeUnavailableException
import com.excellentcalendar.excellent_calendar.bridge.native.NativeEventBridge
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

fun interface ResultDispatcher {
    fun dispatch(block: () -> Unit)
}

fun interface NativeBridgeLogger {
    fun log(method: String, requestId: String?, message: String)
}

class MainThreadResultDispatcher : ResultDispatcher {
    private val handler = Handler(Looper.getMainLooper())

    override fun dispatch(block: () -> Unit) {
        handler.post(block)
    }
}

class AndroidNativeBridgeLogger : NativeBridgeLogger {
    override fun log(method: String, requestId: String?, message: String) {
        Log.d(NativeMethodChannelHandler.LogTag, "method=$method request_id=${requestId ?: "null"} $message")
    }
}

class NativeMethodChannelHandler(
    private val nativeEventBridge: NativeEventBridge,
    private val executor: Executor = Executors.newCachedThreadPool(),
    private val resultDispatcher: ResultDispatcher = MainThreadResultDispatcher(),
    private val logger: NativeBridgeLogger = AndroidNativeBridgeLogger(),
) : MethodChannel.MethodCallHandler, AutoCloseable {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val completion = SingleCompletion(result, resultDispatcher)
        when (call.method) {
            MethodEventCreate -> handleCreateEvent(call, completion)
            MethodEventSearch -> handleSearchEvents(call, completion)
            else -> completion.notImplemented()
        }
    }

    override fun close() {
        if (executor is ExecutorService) {
            executor.shutdownNow()
        }
    }

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
        const val ChannelName = "excellent_calendar/native"
        const val MethodEventCreate = "event.create"
        const val MethodEventSearch = "event.search"
        const val LogTag = "ExcellentCalendarNative"
    }
}
