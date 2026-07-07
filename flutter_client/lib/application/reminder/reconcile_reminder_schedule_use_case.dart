import '../../gateway_interfaces/reminder_native_gateway.dart';
import '../../native_contract/reminder/reconcile_reminder_schedule_dto.dart';
import '../../native_contract/shared/native_invocation.dart';

class ReconcileReminderScheduleUseCase {
  ReconcileReminderScheduleUseCase(this._gateway);

  final ReminderNativeGateway _gateway;
  Future<NativeInvocation<ReconcileReminderScheduleResponseDto>>? _inFlight;

  bool get isReconciling => _inFlight != null;

  Future<NativeInvocation<ReconcileReminderScheduleResponseDto>> execute({
    required ReminderScheduleTrigger triggerSource,
    bool force = false,
  }) {
    final active = _inFlight;
    if (active != null) return active;
    final future = _gateway.reconcileSchedule(
      ReconcileReminderScheduleRequestDto(
        triggerSource: triggerSource,
        force: force,
      ),
    );
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }
}
