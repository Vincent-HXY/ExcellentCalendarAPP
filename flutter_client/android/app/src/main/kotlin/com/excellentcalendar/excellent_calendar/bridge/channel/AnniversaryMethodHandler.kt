package com.excellentcalendar.excellent_calendar.bridge.channel

import com.excellentcalendar.excellent_calendar.bridge.contract.AnniversaryRequestContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.AnniversaryResponseContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.V2JsonRequest
import com.excellentcalendar.excellent_calendar.bridge.native.NativeAnniversaryBridge
import com.excellentcalendar.excellent_calendar.bridge.native.NativeContractProfile
import io.flutter.plugin.common.MethodCall

internal class AnniversaryMethodHandler(
    private val nativeBridge: NativeAnniversaryBridge,
    private val contractProfile: NativeContractProfile,
    private val nativeExecutor: NativeCallExecutor,
    private val orchestrator: AnniversaryMethodOrchestrator,
) : ChannelMethodHandler {
    override val methods = setOf(
        NativeMethodChannelHandler.MethodAnniversaryCreate,
        NativeMethodChannelHandler.MethodAnniversaryUpdate,
        NativeMethodChannelHandler.MethodAnniversaryDelete,
        NativeMethodChannelHandler.MethodAnniversaryDetail,
        NativeMethodChannelHandler.MethodAnniversaryList,
        NativeMethodChannelHandler.MethodAnniversaryPreviewCountdown,
        NativeMethodChannelHandler.MethodAnniversarySetRemindersEnabled,
        NativeMethodChannelHandler.MethodAnniversaryListOccurrences,
    )

    override fun handle(call: MethodCall, completion: SingleCompletion) {
        if (contractProfile != NativeContractProfile.V2) return completion.notImplemented()
        when (call.method) {
            NativeMethodChannelHandler.MethodAnniversaryCreate -> execute(
                call,
                completion,
                AnniversaryRequestContracts::create,
                AnniversaryResponseContracts::nativeDetail,
                nativeBridge::createAnniversary,
                mutation = true,
            )
            NativeMethodChannelHandler.MethodAnniversaryUpdate -> execute(
                call,
                completion,
                AnniversaryRequestContracts::update,
                AnniversaryResponseContracts::nativeDetail,
                nativeBridge::updateAnniversary,
                mutation = true,
            )
            NativeMethodChannelHandler.MethodAnniversaryDelete -> execute(
                call,
                completion,
                AnniversaryRequestContracts::delete,
                AnniversaryResponseContracts::nativeDeleteCommit,
                nativeBridge::deleteAnniversary,
                mutation = true,
                delete = true,
            )
            NativeMethodChannelHandler.MethodAnniversaryDetail -> detail(call, completion)
            NativeMethodChannelHandler.MethodAnniversaryList -> execute(
                call,
                completion,
                AnniversaryRequestContracts::list,
                AnniversaryResponseContracts::list,
                nativeBridge::listAnniversaries,
            )
            NativeMethodChannelHandler.MethodAnniversaryPreviewCountdown -> execute(
                call,
                completion,
                AnniversaryRequestContracts::previewCountdown,
                AnniversaryResponseContracts::countdown,
                nativeBridge::previewAnniversaryCountdown,
            )
            NativeMethodChannelHandler.MethodAnniversarySetRemindersEnabled -> execute(
                call,
                completion,
                AnniversaryRequestContracts::setRemindersEnabled,
                AnniversaryResponseContracts::nativeDetail,
                nativeBridge::setAnniversaryRemindersEnabled,
                mutation = true,
            )
            NativeMethodChannelHandler.MethodAnniversaryListOccurrences -> execute(
                call,
                completion,
                AnniversaryRequestContracts::listOccurrences,
                AnniversaryResponseContracts::occurrences,
                nativeBridge::listAnniversaryOccurrences,
            )
            else -> completion.notImplemented()
        }
    }

    private fun execute(
        call: MethodCall,
        completion: SingleCompletion,
        requestParser: (Any?) -> V2JsonRequest,
        responseValidator: (Any?) -> Unit,
        nativeCall: (String) -> String,
        mutation: Boolean = false,
        delete: Boolean = false,
    ) {
        val request = nativeExecutor.parse(call, completion, requestParser) ?: return
        if (mutation) {
            nativeExecutor.executeOperation(call.method, completion) {
                orchestrator.mutate(
                    method = call.method,
                    nativeJson = nativeCall(request.toJson()),
                    nativeDataValidator = responseValidator,
                    delete = delete,
                )
            }
            return
        }
        nativeExecutor.executeNative(call.method, completion, responseValidator) {
            nativeCall(request.toJson())
        }
    }

    private fun detail(call: MethodCall, completion: SingleCompletion) {
        val request = nativeExecutor.parse(call, completion, AnniversaryRequestContracts::detail) ?: return
        nativeExecutor.executeOperation(call.method, completion) {
            orchestrator.detail(call.method, nativeBridge.getAnniversaryDetail(request.toJson()))
        }
    }
}
