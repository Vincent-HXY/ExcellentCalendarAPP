import '../native_contract/event/create_event_request_dto.dart';
import '../native_contract/event/complete_event_request_dto.dart';
import '../native_contract/event/delete_event_request_dto.dart';
import '../native_contract/event/event_detail_response_dto.dart';
import '../native_contract/event/event_list_response_dto.dart';
import '../native_contract/event/event_occurrence_list_response_dto.dart';
import '../native_contract/event/event_occurrence_operation_request_dto.dart';
import '../native_contract/event/event_occurrence_state_response_dto.dart';
import '../native_contract/event/event_response_dto.dart';
import '../native_contract/event/event_series_operation_request_dto.dart';
import '../native_contract/event/get_event_detail_request_dto.dart';
import '../native_contract/event/list_event_occurrences_request_dto.dart';
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

  Future<NativeInvocation<EventResponseDto>> deleteEvent(
    DeleteEventRequestDto request,
  );

  Future<NativeInvocation<EventListResponseDto>> readEvents(
    SearchEventRequestDto request,
  );

  Future<NativeInvocation<EventDetailResponseDto>> getEventDetail(
    GetEventDetailRequestDto request,
  );

  Future<NativeInvocation<EventResponseDto>> completeEvent(
    CompleteEventRequestDto request,
  );

  Future<NativeInvocation<EventResponseDto>> reopenEvent(
    ReopenEventRequestDto request,
  );

  Future<NativeInvocation<EventOccurrenceListResponseDto>> listOccurrences(
    ListEventOccurrencesRequestDto request,
  );

  Future<NativeInvocation<EventOccurrenceStateResponseDto>> completeOccurrence(
    EventOccurrenceOperationRequestDto request,
  );

  Future<NativeInvocation<EventOccurrenceStateResponseDto>> reopenOccurrence(
    EventOccurrenceOperationRequestDto request,
  );

  Future<NativeInvocation<EventOccurrenceStateResponseDto>> skipOccurrence(
    EventOccurrenceOperationRequestDto request,
  );

  Future<NativeInvocation<EventOccurrenceStateResponseDto>> cancelOccurrence(
    EventOccurrenceOperationRequestDto request,
  );

  Future<NativeInvocation<EventResponseDto>> completeSeries(
    EventSeriesOperationRequestDto request,
  );

  Future<NativeInvocation<EventResponseDto>> reopenSeries(
    EventSeriesOperationRequestDto request,
  );

  Future<NativeInvocation<EventResponseDto>> cancelSeries(
    EventSeriesOperationRequestDto request,
  );
}
