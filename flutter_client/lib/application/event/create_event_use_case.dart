import '../../gateway_interfaces/event_native_gateway.dart';
import '../../native_contract/event/create_event_request_dto.dart';
import '../../native_contract/event/event_response_dto.dart';
import '../../native_contract/shared/native_invocation.dart';
import '../reminder/schedule_pending_reminders_use_case.dart';

class CreateEventUseCase {
  const CreateEventUseCase(
    this._gateway, {
    SchedulePendingRemindersUseCase? schedulePendingRemindersUseCase,
  }) : _schedulePendingRemindersUseCase = schedulePendingRemindersUseCase;

  final EventNativeGateway _gateway;
  final SchedulePendingRemindersUseCase? _schedulePendingRemindersUseCase;

  Future<NativeInvocation<EventResponseDto>> execute(
    CreateEventRequestDto request,
  ) async {
    final invocation = await _gateway.createEvent(request);
    if (invocation.result.ok) {
      await _schedulePendingRemindersUseCase?.execute();
    }
    return invocation;
  }
}
