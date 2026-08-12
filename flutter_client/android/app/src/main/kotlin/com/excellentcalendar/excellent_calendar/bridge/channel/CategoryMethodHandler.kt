package com.excellentcalendar.excellent_calendar.bridge.channel

import com.excellentcalendar.excellent_calendar.bridge.contract.CategoryRequestContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.CategoryResponseContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.V2JsonRequest
import com.excellentcalendar.excellent_calendar.bridge.native.NativeCategoryBridge
import com.excellentcalendar.excellent_calendar.bridge.native.NativeContractProfile
import io.flutter.plugin.common.MethodCall

internal class CategoryMethodHandler(
    private val nativeBridge: NativeCategoryBridge,
    private val contractProfile: NativeContractProfile,
    private val nativeExecutor: NativeCallExecutor,
) : ChannelMethodHandler {
    override val methods = setOf(
        NativeMethodChannelHandler.MethodCategoryList,
        NativeMethodChannelHandler.MethodCategoryCreate,
    )

    override fun handle(call: MethodCall, completion: SingleCompletion) {
        if (contractProfile != NativeContractProfile.V2) return completion.notImplemented()
        when (call.method) {
            NativeMethodChannelHandler.MethodCategoryList -> execute(
                call,
                completion,
                CategoryRequestContracts::list,
                CategoryResponseContracts::list,
                nativeBridge::listCategories,
            )
            NativeMethodChannelHandler.MethodCategoryCreate -> execute(
                call,
                completion,
                CategoryRequestContracts::create,
                CategoryResponseContracts::created,
                nativeBridge::createCategory,
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
