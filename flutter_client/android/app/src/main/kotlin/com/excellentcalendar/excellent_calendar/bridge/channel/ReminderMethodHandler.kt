package com.excellentcalendar.excellent_calendar.bridge.channel

import com.excellentcalendar.excellent_calendar.bridge.contract.CancelReminderRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.CreateReminderRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ListRemindersRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReconcileReminderScheduleContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderListResponseContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderScheduleTrigger
import com.excellentcalendar.excellent_calendar.bridge.contract.SchedulePendingRemindersContract
import com.excellentcalendar.excellent_calendar.bridge.contract.UpdateReminderRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.V2RequestContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.V2ResponseContracts
import com.excellentcalendar.excellent_calendar.bridge.native.NativeBridgeUnavailableException
import com.excellentcalendar.excellent_calendar.bridge.native.NativeContractProfile
import com.excellentcalendar.excellent_calendar.bridge.native.NativeReminderBridge
import com.excellentcalendar.excellent_calendar.bridge.reminder.PendingReminderScheduleService
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderNativeOrchestrator
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderScheduleReconciler
import io.flutter.plugin.common.MethodCall

internal class ReminderMethodHandler(
    private val nativeBridge: NativeReminderBridge,
    private val contractProfile: NativeContractProfile,
    private val nativeExecutor: NativeCallExecutor,
    private val mutationScheduleHook: MutationScheduleHook,
    private val reminderOrchestrator: ReminderNativeOrchestrator?,
    private val pendingReminderScheduleService: PendingReminderScheduleService?,
    private val reminderScheduleCoordinator: ReminderScheduleReconciler?,
) : ChannelMethodHandler {
    override val methods = setOf(
        NativeMethodChannelHandler.MethodReminderCreate,
        NativeMethodChannelHandler.MethodReminderUpdate,
        NativeMethodChannelHandler.MethodReminderCancel,
        NativeMethodChannelHandler.MethodReminderList,
        NativeMethodChannelHandler.MethodReminderSchedulePending,
        NativeMethodChannelHandler.MethodReminderReconcileSchedule,
    )

    override fun handle(call: MethodCall, completion: SingleCompletion) {
        when (call.method) {
            NativeMethodChannelHandler.MethodReminderCreate -> create(call, completion)
            NativeMethodChannelHandler.MethodReminderUpdate -> update(call, completion)
            NativeMethodChannelHandler.MethodReminderCancel -> cancel(call, completion)
            NativeMethodChannelHandler.MethodReminderList -> list(call, completion)
            NativeMethodChannelHandler.MethodReminderSchedulePending -> {
                if (contractProfile == NativeContractProfile.V1) schedulePending(call, completion)
                else completion.notImplemented()
            }
            NativeMethodChannelHandler.MethodReminderReconcileSchedule -> reconcileSchedule(call, completion)
            else -> completion.notImplemented()
        }
    }

    private fun create(call: MethodCall, completion: SingleCompletion) {
        if (contractProfile == NativeContractProfile.V2) {
            val request = nativeExecutor.parse(call, completion, V2RequestContracts::createReminder) ?: return
            executeV2Mutation(call, completion, V2ResponseContracts::reminder) {
                nativeBridge.createReminder(request.toJson())
            }
            return
        }
        val request = nativeExecutor.parse(call, completion, CreateReminderRequestContract::fromMethodArguments)
            ?: return
        nativeExecutor.executeOperation(call.method, completion) {
            requireReminderOrchestrator(call.method).createReminder(request.toJson())
        }
    }

    private fun update(call: MethodCall, completion: SingleCompletion) {
        if (contractProfile == NativeContractProfile.V2) {
            val request = nativeExecutor.parse(call, completion, V2RequestContracts::updateReminder) ?: return
            executeV2Mutation(call, completion, V2ResponseContracts::reminder) {
                nativeBridge.updateReminder(request.toJson())
            }
            return
        }
        val request = nativeExecutor.parse(call, completion, UpdateReminderRequestContract::fromMethodArguments)
            ?: return
        nativeExecutor.executeOperation(call.method, completion) {
            requireReminderOrchestrator(call.method).updateReminder(request.toJson())
        }
    }

    private fun cancel(call: MethodCall, completion: SingleCompletion) {
        if (contractProfile == NativeContractProfile.V2) {
            val request = nativeExecutor.parse(call, completion, V2RequestContracts::cancelReminder) ?: return
            executeV2Mutation(call, completion, V2ResponseContracts::reminder) {
                nativeBridge.cancelReminder(request.toJson())
            }
            return
        }
        val request = nativeExecutor.parse(call, completion, CancelReminderRequestContract::fromMethodArguments)
            ?: return
        nativeExecutor.executeOperation(call.method, completion) {
            requireReminderOrchestrator(call.method).cancelReminder(request.toJson(), request.id)
        }
    }

    private fun list(call: MethodCall, completion: SingleCompletion) {
        if (contractProfile == NativeContractProfile.V2) {
            val request = nativeExecutor.parse(call, completion, V2RequestContracts::listReminders) ?: return
            nativeExecutor.executeNative(call.method, completion, V2ResponseContracts::reminderList) {
                nativeBridge.listReminders(request.toJson())
            }
            return
        }
        val request = nativeExecutor.parse(call, completion, ListRemindersRequestContract::fromMethodArguments)
            ?: return
        nativeExecutor.executeNative(call.method, completion, ReminderListResponseContract::validate) {
            nativeBridge.listReminders(request.toJson())
        }
    }

    private fun schedulePending(call: MethodCall, completion: SingleCompletion) {
        val request = nativeExecutor.parse(call, completion, SchedulePendingRemindersContract::fromMethodArguments)
            ?: return
        nativeExecutor.executeOperation(call.method, completion) {
            val coordinator = reminderScheduleCoordinator
            if (coordinator == null) {
                requirePendingScheduleService(call.method).schedulePending(request)
            } else {
                val reconciled = coordinator.reconcile(
                    ReconcileReminderScheduleContract(
                        ReminderScheduleTrigger.AppStart,
                        force = request.forceReschedule,
                    ),
                )
                if (!reconciled.ok) {
                    reconciled
                } else {
                    @Suppress("UNCHECKED_CAST")
                    val data = reconciled.data as Map<String, Any?>
                    NativeResultContract.success(
                        linkedMapOf(
                            "scheduled_count" to if (data["action"] == "scheduled") 1 else 0,
                            "skipped_count" to 0,
                            "failed_count" to data["failed_count"],
                            "unsupported_method_count" to 0,
                            "has_more" to data["continuation_enqueued"],
                            "failed_reminder_ids" to data["failed_reminder_ids"],
                            "unsupported_reminder_ids" to emptyList<String>(),
                        ),
                    )
                }
            }
        }
    }

    private fun reconcileSchedule(call: MethodCall, completion: SingleCompletion) {
        val request = nativeExecutor.parse(call, completion, ReconcileReminderScheduleContract::fromMethodArguments)
            ?: return
        nativeExecutor.executeOperation(call.method, completion) {
            requireReminderScheduleCoordinator(call.method).reconcile(request)
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

    private fun requireReminderOrchestrator(method: String): ReminderNativeOrchestrator =
        reminderOrchestrator ?: throw NativeBridgeUnavailableException(
            "Reminder orchestration is not configured for $method.",
        )

    private fun requirePendingScheduleService(method: String): PendingReminderScheduleService =
        pendingReminderScheduleService ?: throw NativeBridgeUnavailableException(
            "Pending reminder scheduling is not configured for $method.",
        )

    private fun requireReminderScheduleCoordinator(method: String): ReminderScheduleReconciler =
        reminderScheduleCoordinator ?: throw NativeBridgeUnavailableException(
            "Reminder schedule coordinator is not configured for $method.",
        )
}
