import '../../gateway_interfaces/event_native_gateway.dart';
import '../../native_contract/event/event_occurrence_state_response_dto.dart';
import '../../native_contract/event/reopen_event_request_dto.dart';
import '../../native_contract/shared/native_invocation.dart';

class ReopenEventUseCase {
  const ReopenEventUseCase(this._gateway);

  final EventNativeGateway _gateway;

  Future<NativeInvocation<EventOccurrenceStateResponseDto>> execute(
    ReopenEventRequestDto request,
  ) {
    return _gateway.reopenEvent(request);
  }
}
