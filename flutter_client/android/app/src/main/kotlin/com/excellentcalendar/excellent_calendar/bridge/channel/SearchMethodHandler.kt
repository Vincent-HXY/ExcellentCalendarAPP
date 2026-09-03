package com.excellentcalendar.excellent_calendar.bridge.channel

import com.excellentcalendar.excellent_calendar.android.search.SearchHistoryStore
import com.excellentcalendar.excellent_calendar.android.search.SearchHistoryStoreResult
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.SearchContracts
import com.excellentcalendar.excellent_calendar.bridge.native.NativeContractProfile
import com.excellentcalendar.excellent_calendar.bridge.native.NativeSearchBridge
import io.flutter.plugin.common.MethodCall

/** One module owner for unified Search query and the two Kotlin-local history operations. */
internal class SearchMethodHandler(
    private val nativeBridge: NativeSearchBridge,
    private val historyStore: SearchHistoryStore?,
    private val contractProfile: NativeContractProfile,
    private val nativeExecutor: NativeCallExecutor,
) : ChannelMethodHandler {
    override val methods = setOf(
        NativeMethodChannelHandler.MethodSearchQuery,
        NativeMethodChannelHandler.MethodSearchGetLocalHistory,
        NativeMethodChannelHandler.MethodSearchReplaceLocalHistory,
    )

    override fun handle(call: MethodCall, completion: SingleCompletion) {
        if (contractProfile != NativeContractProfile.V2) {
            nativeExecutor.executeLocal(call.method, completion) {
                NativeResultContract.failure(
                    code = NativeErrorCodes.FeatureNotImplemented,
                    message = "Unified Search requires Native Contract 2.",
                    contractVersion = contractProfile.contractVersion,
                )
            }
            return
        }
        when (call.method) {
            NativeMethodChannelHandler.MethodSearchQuery -> query(call, completion)
            NativeMethodChannelHandler.MethodSearchGetLocalHistory -> getHistory(call, completion)
            NativeMethodChannelHandler.MethodSearchReplaceLocalHistory -> replaceHistory(call, completion)
            else -> completion.notImplemented()
        }
    }

    private fun query(call: MethodCall, completion: SingleCompletion) {
        val request = nativeExecutor.parse(call, completion, SearchContracts::queryRequest) ?: return
        nativeExecutor.executeNative(
            method = call.method,
            completion = completion,
            dataValidator = { data -> SearchContracts.queryResponse(data, request.value) },
        ) {
            nativeBridge.querySearch(request.toJson())
        }
    }

    private fun getHistory(call: MethodCall, completion: SingleCompletion) {
        if (!nativeExecutor.validateEmptyRequest(call, completion)) return
        nativeExecutor.executeOperation(call.method, completion) {
            val store = historyStore ?: return@executeOperation unavailableHistory()
            storeResult(store.get())
        }
    }

    private fun replaceHistory(call: MethodCall, completion: SingleCompletion) {
        val request = nativeExecutor.parse(call, completion, SearchContracts::replaceHistoryRequest) ?: return
        nativeExecutor.executeOperation(call.method, completion) {
            val store = historyStore ?: return@executeOperation unavailableHistory()
            storeResult(store.replace(request.expectedRevision, request.items))
        }
    }

    private fun storeResult(result: SearchHistoryStoreResult): NativeResultContract = when (result) {
        is SearchHistoryStoreResult.Success -> {
            val data = result.snapshot.toMap()
            SearchContracts.historyResponse(data)
            NativeResultContract.success(
                data = data,
                contractVersion = contractProfile.contractVersion,
            )
        }
        is SearchHistoryStoreResult.Failure -> NativeResultContract.failure(
            code = result.code,
            message = result.message,
            details = linkedMapOf("reason" to result.reason),
            retryable = result.retryable,
            contractVersion = contractProfile.contractVersion,
        )
    }

    private fun unavailableHistory(): NativeResultContract = NativeResultContract.failure(
        code = NativeErrorCodes.NativeInternalError,
        message = "Device-local Search history store is unavailable.",
        details = linkedMapOf("reason" to "history_store_not_injected"),
        retryable = true,
        contractVersion = contractProfile.contractVersion,
    )
}
