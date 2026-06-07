import '../../application/event/create_event_use_case.dart';
import '../../native_contract/event/create_event_request_dto.dart';
import '../../native_contract/event/event_response_dto.dart';
import '../../native_contract/shared/native_invocation.dart';

class ScheduleSubmitController {
  const ScheduleSubmitController(this._useCase);

  final CreateEventUseCase _useCase;

  Future<NativeInvocation<EventResponseDto>> submit(
    CreateEventRequestDto request,
  ) {
    return _useCase.execute(request);
  }
}
