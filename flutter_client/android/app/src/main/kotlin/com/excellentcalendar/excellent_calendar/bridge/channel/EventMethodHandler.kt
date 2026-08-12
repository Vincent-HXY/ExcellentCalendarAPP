package com.excellentcalendar.excellent_calendar.bridge.channel

import com.excellentcalendar.excellent_calendar.bridge.contract.CompleteEventRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.CreateEventRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.DeleteEventRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.EventListResponseContract
import com.excellentcalendar.excellent_calendar.bridge.contract.EventResponseContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReopenEventRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.SearchEventRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.UpdateEventRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.V2RequestContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.V2ResponseContracts
import com.excellentcalendar.excellent_calendar.bridge.native.NativeContractProfile
import com.excellentcalendar.excellent_calendar.bridge.native.NativeEventBridge
import io.flutter.plugin.common.MethodCall

internal class EventMethodHandler(
    private val nativeBridge: NativeEventBridge,
    private val contractProfile: NativeContractProfile,
    private val nativeExecutor: NativeCallExecutor,
    private val mutationScheduleHook: MutationScheduleHook,
) : ChannelMethodHandler {
    override val methods = setOf(
        NativeMethodChannelHandler.MethodEventCreate,
        NativeMethodChannelHandler.MethodEventUpdate,
        NativeMethodChannelHandler.MethodEventDelete,
        NativeMethodChannelHandler.MethodEventSearch,
        NativeMethodChannelHandler.MethodEventDetail,
        NativeMethodChannelHandler.MethodEventComplete,
        NativeMethodChannelHandler.MethodEventReopen,
        NativeMethodChannelHandler.MethodEventListOccurrences,
        NativeMethodChannelHandler.MethodEventOccurrenceComplete,
        NativeMethodChannelHandler.MethodEventOccurrenceReopen,
        NativeMethodChannelHandler.MethodEventOccurrenceSkip,
        NativeMethodChannelHandler.MethodEventOccurrenceCancel,
        NativeMethodChannelHandler.MethodEventSeriesComplete,
        NativeMethodChannelHandler.MethodEventSeriesReopen,
        NativeMethodChannelHandler.MethodEventSeriesCancel,
    )

    override fun handle(call: MethodCall, completion: SingleCompletion) {
        when (call.method) {
            NativeMethodChannelHandler.MethodEventCreate -> create(call, completion)
            NativeMethodChannelHandler.MethodEventUpdate -> update(call, completion)
            NativeMethodChannelHandler.MethodEventDelete -> delete(call, completion)
            NativeMethodChannelHandler.MethodEventSearch -> search(call, completion)
            NativeMethodChannelHandler.MethodEventDetail -> detail(call, completion)
            NativeMethodChannelHandler.MethodEventComplete -> complete(call, completion)
            NativeMethodChannelHandler.MethodEventReopen -> reopen(call, completion)
            NativeMethodChannelHandler.MethodEventListOccurrences -> listOccurrences(call, completion)
            NativeMethodChannelHandler.MethodEventOccurrenceComplete ->
                occurrenceOperation(call, completion, nativeBridge::completeEventOccurrence)
            NativeMethodChannelHandler.MethodEventOccurrenceReopen ->
                occurrenceOperation(call, completion, nativeBridge::reopenEventOccurrence)
            NativeMethodChannelHandler.MethodEventOccurrenceSkip ->
                occurrenceOperation(call, completion, nativeBridge::skipEventOccurrence)
            NativeMethodChannelHandler.MethodEventOccurrenceCancel ->
                occurrenceOperation(call, completion, nativeBridge::cancelEventOccurrence)
            NativeMethodChannelHandler.MethodEventSeriesComplete ->
                seriesOperation(call, completion, nativeBridge::completeEventSeries)
            NativeMethodChannelHandler.MethodEventSeriesReopen ->
                seriesOperation(call, completion, nativeBridge::reopenEventSeries)
            NativeMethodChannelHandler.MethodEventSeriesCancel ->
                seriesOperation(call, completion, nativeBridge::cancelEventSeries)
            else -> completion.notImplemented()
        }
    }

    private fun create(call: MethodCall, completion: SingleCompletion) {
        if (contractProfile == NativeContractProfile.V2) {
            val request = nativeExecutor.parse(call, completion, V2RequestContracts::createEvent) ?: return
            executeV2Mutation(call, completion, V2ResponseContracts::event) {
                nativeBridge.createEvent(request.toJson())
            }
            return
        }
        val request = nativeExecutor.parse(call, completion, CreateEventRequestContract::fromMethodArguments) ?: return
        nativeExecutor.executeNative(call.method, completion, EventResponseContract::validate) {
            nativeBridge.createEvent(request.toJson())
        }
    }

    private fun update(call: MethodCall, completion: SingleCompletion) {
        if (contractProfile == NativeContractProfile.V2) {
            val request = nativeExecutor.parse(call, completion, V2RequestContracts::updateEvent) ?: return
            executeV2Mutation(call, completion, V2ResponseContracts::event) {
                nativeBridge.updateEvent(request.toJson())
            }
            return
        }
        val request = nativeExecutor.parse(call, completion, UpdateEventRequestContract::fromMethodArguments) ?: return
        nativeExecutor.executeNative(call.method, completion, EventResponseContract::validate) {
            nativeBridge.updateEvent(request.toJson())
        }
    }

    private fun delete(call: MethodCall, completion: SingleCompletion) {
        if (contractProfile == NativeContractProfile.V2) {
            val request = nativeExecutor.parse(call, completion, V2RequestContracts::deleteEvent) ?: return
            executeV2Mutation(call, completion, V2ResponseContracts::event) {
                nativeBridge.deleteEvent(request.toJson())
            }
            return
        }
        val request = nativeExecutor.parse(call, completion, DeleteEventRequestContract::fromMethodArguments) ?: return
        nativeExecutor.executeNative(call.method, completion, EventResponseContract::validate) {
            nativeBridge.deleteEvent(request.toJson())
        }
    }

    private fun search(call: MethodCall, completion: SingleCompletion) {
        if (contractProfile == NativeContractProfile.V2) {
            val request = nativeExecutor.parse(call, completion, V2RequestContracts::searchEvent) ?: return
            nativeExecutor.executeNative(call.method, completion, V2ResponseContracts::eventList) {
                nativeBridge.searchEvents(request.toJson())
            }
            return
        }
        val request = nativeExecutor.parse(call, completion, SearchEventRequestContract::fromMethodArguments) ?: return
        nativeExecutor.executeNative(call.method, completion, EventListResponseContract::validate) {
            nativeBridge.searchEvents(request.toJson())
        }
    }

    private fun complete(call: MethodCall, completion: SingleCompletion) {
        if (contractProfile == NativeContractProfile.V2) {
            val request = nativeExecutor.parse(call, completion, V2RequestContracts::completeEvent) ?: return
            executeV2Mutation(call, completion, V2ResponseContracts::event) {
                nativeBridge.completeEvent(request.toJson())
            }
            return
        }
        val request = nativeExecutor.parse(call, completion, CompleteEventRequestContract::fromMethodArguments) ?: return
        nativeExecutor.executeNative(call.method, completion, EventResponseContract::validate) {
            nativeBridge.completeEvent(request.toJson())
        }
    }

    private fun reopen(call: MethodCall, completion: SingleCompletion) {
        if (contractProfile == NativeContractProfile.V2) {
            val request = nativeExecutor.parse(call, completion, V2RequestContracts::reopenEvent) ?: return
            executeV2Mutation(call, completion, V2ResponseContracts::event) {
                nativeBridge.reopenEvent(request.toJson())
            }
            return
        }
        val request = nativeExecutor.parse(call, completion, ReopenEventRequestContract::fromMethodArguments) ?: return
        nativeExecutor.executeNative(call.method, completion, EventResponseContract::validate) {
            nativeBridge.reopenEvent(request.toJson())
        }
    }

    private fun detail(call: MethodCall, completion: SingleCompletion) {
        if (contractProfile != NativeContractProfile.V2) return completion.notImplemented()
        val request = nativeExecutor.parse(call, completion, V2RequestContracts::eventId) ?: return
        nativeExecutor.executeNative(call.method, completion, V2ResponseContracts::eventDetail) {
            nativeBridge.getEventDetail(request.toJson())
        }
    }

    private fun listOccurrences(call: MethodCall, completion: SingleCompletion) {
        if (contractProfile != NativeContractProfile.V2) return completion.notImplemented()
        val request = nativeExecutor.parse(call, completion, V2RequestContracts::listOccurrences) ?: return
        nativeExecutor.executeNative(call.method, completion, V2ResponseContracts::occurrenceList) {
            nativeBridge.listEventOccurrences(request.toJson())
        }
    }

    private fun occurrenceOperation(
        call: MethodCall,
        completion: SingleCompletion,
        nativeCall: (String) -> String,
    ) {
        if (contractProfile != NativeContractProfile.V2) return completion.notImplemented()
        val request = nativeExecutor.parse(call, completion, V2RequestContracts::occurrenceOperation) ?: return
        executeV2Mutation(call, completion, V2ResponseContracts::occurrenceState) {
            nativeCall(request.toJson())
        }
    }

    private fun seriesOperation(
        call: MethodCall,
        completion: SingleCompletion,
        nativeCall: (String) -> String,
    ) {
        if (contractProfile != NativeContractProfile.V2) return completion.notImplemented()
        val request = nativeExecutor.parse(call, completion, V2RequestContracts::seriesOperation) ?: return
        executeV2Mutation(call, completion, V2ResponseContracts::event) {
            nativeCall(request.toJson())
        }
    }

    private fun executeV2Mutation(
        call: MethodCall,
        completion: SingleCompletion,
        dataValidator: (Any?) -> Unit,
        nativeCall: () -> String,
    ) {
        nativeExecutor.executeNative(
            call.method,
            completion,
            dataValidator,
            afterSuccess = { mutationScheduleHook.afterMutation(call.method) },
            nativeCall = nativeCall,
        )
    }
}
