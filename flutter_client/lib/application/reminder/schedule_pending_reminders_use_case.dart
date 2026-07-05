import '../../gateway_interfaces/reminder_native_gateway.dart';
import '../../native_contract/reminder/schedule_pending_reminders_dto.dart';
import '../../native_contract/shared/native_invocation.dart';

class SchedulePendingRemindersCommand {
  const SchedulePendingRemindersCommand({
    this.horizonMinutes = 10080,
    this.limit = 128,
    this.forceReschedule = false,
  });

  final int horizonMinutes;
  final int limit;
  final bool forceReschedule;

  SchedulePendingRemindersRequestDto toRequestDto(DateTime now) {
    if (horizonMinutes < 1) {
      throw const FormatException('horizonMinutes must be positive.');
    }
    return SchedulePendingRemindersRequestDto(
      fromAt: now,
      toAt: now.add(Duration(minutes: horizonMinutes)),
      limit: limit,
      forceReschedule: forceReschedule,
    );
  }
}

class SchedulePendingRemindersUseCase {
  SchedulePendingRemindersUseCase(this._gateway, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final ReminderNativeGateway _gateway;
  final DateTime Function() _clock;
  Future<NativeInvocation<SchedulePendingRemindersResponseDto>>? _inFlight;

  bool get isScheduling => _inFlight != null;

  Future<NativeInvocation<SchedulePendingRemindersResponseDto>> execute([
    SchedulePendingRemindersCommand command =
        const SchedulePendingRemindersCommand(),
  ]) {
    final active = _inFlight;
    if (active != null) return active;

    final future = _gateway.schedulePending(command.toRequestDto(_clock()));
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    });
  }
}
