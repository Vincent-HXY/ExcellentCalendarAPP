import 'event_list_response_dto.dart';
import 'event_occurrence_state_response_dto.dart';
import 'event_response_dto.dart';

class EventMapper {
  const EventMapper._();

  static EventResponseDto eventResponseFromNativeData(Object? rawData) {
    if (rawData is! Map<String, dynamic>) {
      throw const FormatException('EventResponse data must be object.');
    }
    return EventResponseDto.fromJson(rawData);
  }

  static EventListResponseDto eventListResponseFromNativeData(Object? rawData) {
    if (rawData is! Map<String, dynamic>) {
      throw const FormatException('EventListResponse data must be object.');
    }
    return EventListResponseDto.fromJson(rawData);
  }

  static EventOccurrenceStateResponseDto eventOccurrenceStateFromNativeData(
    Object? rawData,
  ) {
    if (rawData is! Map<String, dynamic>) {
      throw const FormatException(
        'EventOccurrenceStateResponse data must be object.',
      );
    }
    return EventOccurrenceStateResponseDto.fromJson(rawData);
  }
}
