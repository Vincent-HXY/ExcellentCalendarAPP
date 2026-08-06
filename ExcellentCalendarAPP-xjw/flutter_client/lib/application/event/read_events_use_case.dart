import '../../gateway_interfaces/event_native_gateway.dart';
import '../../native_contract/event/event_list_response_dto.dart';
import '../../native_contract/event/search_event_request_dto.dart';
import '../../native_contract/shared/native_invocation.dart';

class ReadEventsUseCase {
  const ReadEventsUseCase(this._gateway);

  final EventNativeGateway _gateway;

  Future<NativeInvocation<EventListResponseDto>> execute({
    SearchEventRequestDto request = const SearchEventRequestDto(),
  }) {
    return _gateway.readEvents(request);
  }
}
