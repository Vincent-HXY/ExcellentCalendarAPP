package com.excellentcalendar.excellent_calendar.bridge.channel

import com.excellentcalendar.excellent_calendar.bridge.contract.CalendarContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.V2JsonRequest
import com.excellentcalendar.excellent_calendar.bridge.native.NativeCalendarViewBridge
import com.excellentcalendar.excellent_calendar.bridge.native.NativeContractProfile
import io.flutter.plugin.common.MethodCall

/** Thin MethodChannel router for the two read-only Calendar View queries. */
internal class CalendarMethodHandler(
    private val nativeBridge: NativeCalendarViewBridge,
    private val contractProfile: NativeContractProfile,
    private val nativeExecutor: NativeCallExecutor,
) : ChannelMethodHandler {
    override val methods = setOf(
        NativeMethodChannelHandler.MethodCalendarRangeSummary,
        NativeMethodChannelHandler.MethodCalendarListDayItems,
    )

    override fun handle(call: MethodCall, completion: SingleCompletion) {
        if (contractProfile != NativeContractProfile.V2) {
            nativeExecutor.executeLocal(call.method, completion) {
                NativeResultContract.failure(
                    code = NativeErrorCodes.FeatureNotImplemented,
                    message = "Calendar View requires Native Contract 2.",
                    contractVersion = contractProfile.contractVersion,
                )
            }
            return
        }
        when (call.method) {
            NativeMethodChannelHandler.MethodCalendarRangeSummary -> query(
                call,
                completion,
                CalendarContracts::rangeSummaryRequest,
                { data, request -> CalendarContracts.rangeSummaryResponse(data, request.value) },
                nativeBridge::calendarRangeSummary,
            )
            NativeMethodChannelHandler.MethodCalendarListDayItems -> query(
                call,
                completion,
                CalendarContracts::listDayItemsRequest,
                { data, request -> CalendarContracts.dayItemPage(data, request.value) },
                nativeBridge::calendarListDayItems,
            )
            else -> completion.notImplemented()
        }
    }

    private fun query(
        call: MethodCall,
        completion: SingleCompletion,
        parser: (Any?) -> V2JsonRequest,
        validator: (Any?, V2JsonRequest) -> Unit,
        nativeCall: (String) -> String,
    ) {
        val request = nativeExecutor.parse(call, completion, parser) ?: return
        nativeExecutor.executeNative(
            method = call.method,
            completion = completion,
            dataValidator = { data -> validator(data, request) },
        ) {
            nativeCall(request.toJson())
        }
    }
}
