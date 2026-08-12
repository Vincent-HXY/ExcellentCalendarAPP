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
) : ChannelMethodHandler {
    override val methods = setOf(
        NativeMethodChannelHandler.MethodAnniversaryCreate,
        NativeMethodChannelHandler.MethodAnniversaryUpdate,
        NativeMethodChannelHandler.MethodAnniversaryDelete,
        NativeMethodChannelHandler.MethodAnniversaryDetail,
        NativeMethodChannelHandler.MethodAnniversaryList,
        NativeMethodChannelHandler.MethodAnniversaryPreviewCountdown,
    )

    override fun handle(call: MethodCall, completion: SingleCompletion) {
        if (contractProfile != NativeContractProfile.V2) return completion.notImplemented()
        when (call.method) {
            NativeMethodChannelHandler.MethodAnniversaryCreate -> execute(
                call,
                completion,
                AnniversaryRequestContracts::create,
                AnniversaryResponseContracts::detail,
                nativeBridge::createAnniversary,
            )
            NativeMethodChannelHandler.MethodAnniversaryUpdate -> execute(
                call,
                completion,
                AnniversaryRequestContracts::update,
                AnniversaryResponseContracts::detail,
                nativeBridge::updateAnniversary,
            )
            NativeMethodChannelHandler.MethodAnniversaryDelete -> execute(
                call,
                completion,
                AnniversaryRequestContracts::delete,
                AnniversaryResponseContracts::deleted,
                nativeBridge::deleteAnniversary,
            )
            NativeMethodChannelHandler.MethodAnniversaryDetail -> execute(
                call,
                completion,
                AnniversaryRequestContracts::detail,
                AnniversaryResponseContracts::detail,
                nativeBridge::getAnniversaryDetail,
            )
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
            else -> completion.notImplemented()
        }
    }

    private fun execute(
        call: MethodCall,
        completion: SingleCompletion,
        requestParser: (Any?) -> V2JsonRequest,
        responseValidator: (Any?) -> Unit,
        nativeCall: (String) -> String,
    ) {
        val request = nativeExecutor.parse(call, completion, requestParser) ?: return
        nativeExecutor.executeNative(call.method, completion, responseValidator) {
            nativeCall(request.toJson())
        }
    }
}
