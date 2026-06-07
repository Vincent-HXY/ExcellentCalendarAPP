import '../../gateway_interfaces/event_native_gateway.dart';
import '../../native_contract/event/create_event_request_dto.dart';
import '../../native_contract/event/event_response_dto.dart';
import '../../native_contract/shared/native_invocation.dart';

class CreateEventUseCase {
  const CreateEventUseCase(this._gateway);

  final EventNativeGateway _gateway;

  Future<NativeInvocation<EventResponseDto>> execute(
    CreateEventRequestDto request,
  ) {
    return _gateway.createEvent(request);
  }
}
