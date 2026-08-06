import '../common/pagination_response_dto.dart';
import '../shared/contract_json_object.dart';
import 'event_response_dto.dart';

class EventListResponseDto {
  const EventListResponseDto({required this.items, required this.pagination});

  final List<EventResponseDto> items;
  final PaginationResponseDto pagination;

  factory EventListResponseDto.fromJson(Map<String, dynamic> json) {
    ContractJsonObject.rejectUnknownKeys(json, {
      'items',
      'pagination',
    }, 'EventListResponse');
    ContractJsonObject.requireKeys(json, {
      'items',
      'pagination',
    }, 'EventListResponse');

    final items = json['items'];
    final pagination = json['pagination'];
    if (items is! List) {
      throw const FormatException('EventListResponse.items must be array.');
    }
    if (pagination is! Map<String, dynamic>) {
      throw const FormatException(
        'EventListResponse.pagination must be object.',
      );
    }
    return EventListResponseDto(
      items: items
          .map((item) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException(
                'EventListResponse item must be object.',
              );
            }
            return EventResponseDto.fromJson(item);
          })
          .toList(growable: false),
      pagination: PaginationResponseDto.fromJson(pagination),
    );
  }
}
