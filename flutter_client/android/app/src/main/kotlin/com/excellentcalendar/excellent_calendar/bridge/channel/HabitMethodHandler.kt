package com.excellentcalendar.excellent_calendar.bridge.channel

import com.excellentcalendar.excellent_calendar.bridge.contract.HabitContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.V2JsonRequest
import com.excellentcalendar.excellent_calendar.bridge.native.NativeHabitBridge
import io.flutter.plugin.common.MethodCall

internal class HabitMethodHandler(
    private val bridge: NativeHabitBridge,
    private val profile: com.excellentcalendar.excellent_calendar.bridge.native.NativeContractProfile,
    private val calls: NativeCallExecutor,
    private val orchestrator: HabitMutationOrchestrator,
) : ChannelMethodHandler {
    override val methods = setOf(
        NativeMethodChannelHandler.MethodHabitCreate,
        NativeMethodChannelHandler.MethodHabitUpdate,
        NativeMethodChannelHandler.MethodHabitList,
        NativeMethodChannelHandler.MethodHabitDetail,
        NativeMethodChannelHandler.MethodHabitEnd,
        NativeMethodChannelHandler.MethodHabitDelete,
        NativeMethodChannelHandler.MethodHabitCheckIn,
        NativeMethodChannelHandler.MethodHabitClearCheckIn,
        NativeMethodChannelHandler.MethodHabitListDailyStatuses,
        NativeMethodChannelHandler.MethodHabitSetReminder,
    )

    override fun handle(call: MethodCall, completion: SingleCompletion) {
        if (profile.contractVersion != 2) {
            calls.executeLocal(call.method, completion) {
                com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract.failure(
                    com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes.FeatureNotImplemented,
                    "Habit V1 requires Native Contract 2.",
                    contractVersion = profile.contractVersion,
                )
            }
            return
        }
        when (call.method) {
            NativeMethodChannelHandler.MethodHabitCreate -> mutation(call, completion, HabitContracts::create, bridge::createHabit, HabitMutationOrchestrator.Shape.Mutation)
            NativeMethodChannelHandler.MethodHabitUpdate -> mutation(call, completion, HabitContracts::update, bridge::updateHabit, HabitMutationOrchestrator.Shape.Mutation)
            NativeMethodChannelHandler.MethodHabitEnd -> mutation(call, completion, HabitContracts::end, bridge::endHabit, HabitMutationOrchestrator.Shape.Mutation)
            NativeMethodChannelHandler.MethodHabitDelete -> mutation(call, completion, HabitContracts::delete, bridge::deleteHabit, HabitMutationOrchestrator.Shape.Delete)
            NativeMethodChannelHandler.MethodHabitCheckIn -> mutation(call, completion, HabitContracts::manualCheckInCommand, bridge::checkInHabit, HabitMutationOrchestrator.Shape.CheckIn)
            NativeMethodChannelHandler.MethodHabitClearCheckIn -> mutation(call, completion, HabitContracts::clearCheckIn, bridge::clearHabitCheckIn, HabitMutationOrchestrator.Shape.CheckIn)
            NativeMethodChannelHandler.MethodHabitSetReminder -> mutation(call, completion, HabitContracts::setReminder, bridge::setHabitReminder, HabitMutationOrchestrator.Shape.Mutation)
            NativeMethodChannelHandler.MethodHabitList -> query(call, completion, HabitContracts::list, HabitContracts::listResponse, bridge::listHabits)
            NativeMethodChannelHandler.MethodHabitDetail -> query(call, completion, HabitContracts::detail, HabitContracts::detailResponse, bridge::getHabitDetail)
            NativeMethodChannelHandler.MethodHabitListDailyStatuses -> query(call, completion, HabitContracts::listDailyStatuses, HabitContracts::dailyStatusListResponse, bridge::listHabitDailyStatuses)
            else -> completion.notImplemented()
        }
    }

    private fun mutation(
        call: MethodCall,
        completion: SingleCompletion,
        parser: (Any?) -> V2JsonRequest,
        native: (String) -> String,
        shape: HabitMutationOrchestrator.Shape,
    ) {
        val request = calls.parse(call, completion, parser) ?: return
        calls.executeOperation(call.method, completion) {
            orchestrator.mutate(call.method, native(request.toJson()), shape)
        }
    }

    private fun query(
        call: MethodCall,
        completion: SingleCompletion,
        parser: (Any?) -> V2JsonRequest,
        validator: (Any?) -> Unit,
        native: (String) -> String,
    ) {
        val request = calls.parse(call, completion, parser) ?: return
        calls.executeNative(call.method, completion, validator) { native(request.toJson()) }
    }
}
