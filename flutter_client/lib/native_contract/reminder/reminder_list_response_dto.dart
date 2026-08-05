import '../common/pagination_response_dto.dart';
import '../shared/contract_value.dart';
import 'reminder_response_dto.dart';

class ReminderListResponseDto {
  const ReminderListResponseDto({
    required this.items,
    required this.pagination,
  });

  final List<ReminderResponseDto> items;
  final PaginationResponseDto pagination;

  factory ReminderListResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'items',
      'pagination',
    }, 'ReminderListResponse');
    final rawItems = json['items'];
    final rawPagination = json['pagination'];
    if (rawItems is! List ||
        rawItems.any((item) => item is! Map<String, dynamic>) ||
        rawPagination is! Map<String, dynamic>) {
      throw const FormatException('ReminderListResponse shape is invalid.');
    }
    return ReminderListResponseDto(
      items: List<ReminderResponseDto>.unmodifiable(
        rawItems.cast<Map<String, dynamic>>().map(ReminderResponseDto.fromJson),
      ),
      pagination: PaginationResponseDto.fromJson(rawPagination),
    );
  }
}
