import '../shared/contract_value.dart';
import 'event_occurrence_response_dto.dart';

class EventOccurrenceListResponseDto {
  const EventOccurrenceListResponseDto({
    required this.items,
    required this.hasMore,
    required this.nextCursor,
  });

  final List<EventOccurrenceResponseDto> items;
  final bool hasMore;
  final String? nextCursor;

  factory EventOccurrenceListResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'items',
      'has_more',
      'next_cursor',
    }, 'EventOccurrenceListResponse');
    final rawItems = json['items'];
    if (rawItems is! List ||
        rawItems.length > 200 ||
        rawItems.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException(
        'EventOccurrenceListResponse.items is invalid.',
      );
    }
    return EventOccurrenceListResponseDto(
      items: List<EventOccurrenceResponseDto>.unmodifiable(
        rawItems.cast<Map<String, dynamic>>().map(
          EventOccurrenceResponseDto.fromJson,
        ),
      ),
      hasMore: ContractValue.boolean(
        json,
        'has_more',
        'EventOccurrenceListResponse',
      ),
      nextCursor: ContractValue.optionalString(
        json,
        'next_cursor',
        'EventOccurrenceListResponse',
      ),
    );
  }
}
