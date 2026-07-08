import '../native_contract/event/create_event_request_dto.dart';
import '../native_contract/event/complete_event_request_dto.dart';
import '../native_contract/event/event_list_response_dto.dart';
import '../native_contract/event/event_response_dto.dart';
import '../native_contract/event/reopen_event_request_dto.dart';
import '../native_contract/event/search_event_request_dto.dart';
import '../native_contract/event/update_event_request_dto.dart';
import '../native_contract/shared/native_invocation.dart';

abstract interface class EventNativeGateway {
  Future<NativeInvocation<EventResponseDto>> createEvent(
    CreateEventRequestDto request,
  );

  Future<NativeInvocation<EventResponseDto>> updateEvent(
    UpdateEventRequestDto request,
  );

  Future<NativeInvocation<EventListResponseDto>> readEvents(
    SearchEventRequestDto request,
  );

  Future<NativeInvocation<EventResponseDto>> completeEvent(
    CompleteEventRequestDto request,
  );

  Future<NativeInvocation<EventResponseDto>> reopenEvent(
    ReopenEventRequestDto request,
  );
}
