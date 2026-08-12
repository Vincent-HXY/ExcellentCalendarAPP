package com.excellentcalendar.excellent_calendar.bridge.channel

import com.excellentcalendar.excellent_calendar.bridge.contract.EmptyRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeContractViolation
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.native.NativeBridgeUnavailableException
import com.excellentcalendar.excellent_calendar.bridge.native.NativeContractProfile
import io.flutter.plugin.common.MethodCall
import java.util.concurrent.Executor

/**
 * Shared execution and NativeResult adaptation for module handlers.
 *
 * This class deliberately has no knowledge of Event, Reminder, Notification, or any method name.
 */
internal class NativeCallExecutor(
    private val executor: Executor,
    private val contractProfile: NativeContractProfile,
    private val logger: NativeBridgeLogger,
) {
    fun <T> parse(
        call: MethodCall,
        completion: SingleCompletion,
        parser: (Any?) -> T,
    ): T? = try {
        parser(call.arguments)
    } catch (error: NativeContractViolation) {
        completion.success(contractFailure(call.method, error).toMap())
        null
    }

    fun validateEmptyRequest(call: MethodCall, completion: SingleCompletion): Boolean {
        return try {
            EmptyRequestContract.validate(call.arguments)
            true
        } catch (error: NativeContractViolation) {
            completion.success(contractFailure(call.method, error).toMap())
            false
        }
    }

    fun executeLocal(
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
        completeProfiled(method, completion, nativeResult)
    }

    fun executeNative(
        method: String,
        completion: SingleCompletion,
        dataValidator: (Any?) -> Unit,
        afterSuccess: (() -> Unit)? = null,
        nativeCall: () -> String,
    ) {
        submit(method, completion) {
            val nativeResult = try {
                val nativeJson = nativeCall()
                NativeResultContract.fromJson(nativeJson, contractProfile.contractVersion, dataValidator)
            } catch (error: NativeContractViolation) {
                contractFailure(method, error)
            } catch (error: NativeBridgeUnavailableException) {
                nativeUnavailableFailure(method, error)
            } catch (error: UnsatisfiedLinkError) {
                nativeUnavailableFailure(method, error)
            } catch (error: Throwable) {
                nativeInternalFailure(method, error)
            }
            if (nativeResult.ok) afterSuccess?.invoke()
            complete(method, completion, nativeResult)
        }
    }

    fun executeOperation(
        method: String,
        completion: SingleCompletion,
        operation: () -> NativeResultContract,
    ) {
        submit(method, completion) {
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
            complete(method, completion, nativeResult)
        }
    }

    fun complete(method: String, completion: SingleCompletion, nativeResult: NativeResultContract) {
        logger.log(method, nativeResult.requestId, "completed ok=${nativeResult.ok}")
        completion.success(nativeResult.toMap())
    }

    fun completeInternalFailure(method: String, completion: SingleCompletion, error: Throwable) {
        completion.success(nativeInternalFailure(method, error).toMap())
    }

    private fun completeProfiled(
        method: String,
        completion: SingleCompletion,
        nativeResult: NativeResultContract,
    ) {
        complete(method, completion, nativeResult.copy(contractVersion = contractProfile.contractVersion))
    }

    private fun submit(method: String, completion: SingleCompletion, block: () -> Unit) {
        try {
            executor.execute(block)
        } catch (error: Throwable) {
            completeInternalFailure(method, completion, error)
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
            contractVersion = contractProfile.contractVersion,
        )
    }

    private fun nativeUnavailableFailure(method: String, error: Throwable): NativeResultContract {
        logger.log(method, null, "native unavailable type=${error.javaClass.simpleName}")
        return NativeResultContract.failure(
            code = NativeErrorCodes.NativeInternalError,
            message = "Native calendar core bridge is unavailable.",
            details = linkedMapOf(
                "method" to method,
                "reason" to error.javaClass.simpleName,
            ),
            contractVersion = contractProfile.contractVersion,
        )
    }

    private fun nativeInternalFailure(method: String, error: Throwable): NativeResultContract {
        logger.log(method, null, "native call failed type=${error.javaClass.simpleName}")
        return NativeResultContract.failure(
            code = NativeErrorCodes.NativeInternalError,
            message = "Native calendar core bridge call failed.",
            details = linkedMapOf(
                "method" to method,
                "reason" to error.javaClass.simpleName,
            ),
            contractVersion = contractProfile.contractVersion,
        )
    }
}
