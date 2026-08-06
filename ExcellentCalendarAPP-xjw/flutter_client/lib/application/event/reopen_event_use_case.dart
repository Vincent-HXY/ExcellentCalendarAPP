import '../../gateway_interfaces/event_native_gateway.dart';
import '../../native_contract/event/event_response_dto.dart';
import '../../native_contract/event/reopen_event_request_dto.dart';
import '../../native_contract/reminder/reconcile_reminder_schedule_dto.dart';
import '../../native_contract/shared/native_invocation.dart';
import '../reminder/reconcile_reminder_schedule_use_case.dart';

class ReopenEventUseCase {
  ReopenEventUseCase(
    this._gateway, {
    ReconcileReminderScheduleUseCase? reconcileReminderScheduleUseCase,
  }) : _reconcileReminderScheduleUseCase = reconcileReminderScheduleUseCase;

  final EventNativeGateway _gateway;
  final ReconcileReminderScheduleUseCase? _reconcileReminderScheduleUseCase;
  NativeInvocation<ReconcileReminderScheduleResponseDto>?
  lastReconcileInvocation;

  Future<NativeInvocation<EventResponseDto>> execute(
    ReopenEventRequestDto request,
  ) async {
    final invocation = await _gateway.reopenEvent(request);
    if (invocation.result.ok) {
      lastReconcileInvocation = await _reconcileReminderScheduleUseCase
          ?.execute(
            triggerSource: ReminderScheduleTrigger.mutation,
            force: true,
          );
    }
    return invocation;
  }
}
