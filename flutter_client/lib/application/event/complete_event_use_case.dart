import '../../gateway_interfaces/event_native_gateway.dart';
import '../../native_contract/event/complete_event_request_dto.dart';
import '../../native_contract/event/event_response_dto.dart';
import '../../native_contract/shared/native_invocation.dart';

class CompleteEventUseCase {
  const CompleteEventUseCase(this._gateway);

  final EventNativeGateway _gateway;

  Future<NativeInvocation<EventResponseDto>> execute(
    CompleteEventRequestDto request,
  ) {
    return _gateway.completeEvent(request);
  }
}
