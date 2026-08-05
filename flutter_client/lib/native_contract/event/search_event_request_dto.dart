import '../common/pagination_request_dto.dart';
import '../shared/contract_value.dart';

class SearchEventRequestDto {
  const SearchEventRequestDto({
    this.keyword,
    this.startAtFrom,
    this.startAtTo,
    this.startDateFrom,
    this.startDateTo,
    this.status = const [],
    this.categoryIds = const [],
    this.importance = const [],
    this.location,
    this.hasRecurrence,
    this.source = const [],
    this.includeDeleted = false,
    this.pagination = const PaginationRequestDto(),
    this.sortBy = 'start',
    this.sortDirection = 'asc',
  });

  static const _statuses = {'active', 'completed', 'cancelled', 'archived'};
  static const _importanceValues = {
    'unimportant_noturgent',
    'important_noturgent',
    'unimportant_urgent',
    'important_urgent',
  };
  static const _sourceValues = {
    'manual',
    'ai_extraction',
    'sync',
    'import',
    'wechat',
  };
  static const _sortValues = {
    null,
    'start',
    'created_at',
    'updated_at',
    'importance',
    'title',
  };

  final String? keyword;
  final DateTime? startAtFrom;
  final DateTime? startAtTo;
  final String? startDateFrom;
  final String? startDateTo;
  final List<String> status;
  final List<String> categoryIds;
  final List<String> importance;
  final String? location;
  final bool? hasRecurrence;
  final List<String> source;
  final bool includeDeleted;
  final PaginationRequestDto pagination;
  final String? sortBy;
  final String? sortDirection;

  Map<String, dynamic> toJson() {
    for (final value in status) {
      ContractValue.validateEnum(value, _statuses, 'EventStatus');
    }
    for (final value in importance) {
      ContractValue.validateEnum(value, _importanceValues, 'Importance');
    }
    for (final value in source) {
      ContractValue.validateEnum(value, _sourceValues, 'SearchEvent source');
    }
    if (!_sortValues.contains(sortBy)) {
      throw FormatException('Unknown SearchEvent sort_by: $sortBy');
    }
    if (sortDirection != null &&
        sortDirection != 'asc' &&
        sortDirection != 'desc') {
      throw FormatException('Unknown SortDirection: $sortDirection');
    }
    if (startDateFrom != null) {
      ContractValue.validateLocalDate(
        startDateFrom!,
        field: 'SearchEventRequest.start_date_from',
      );
    }
    if (startDateTo != null) {
      ContractValue.validateLocalDate(
        startDateTo!,
        field: 'SearchEventRequest.start_date_to',
      );
    }
    return {
      'keyword': keyword,
      'start_at_from': startAtFrom == null
          ? null
          : ContractValue.formatUtcDateTime(
              startAtFrom!,
              field: 'SearchEventRequest.start_at_from',
            ),
      'start_at_to': startAtTo == null
          ? null
          : ContractValue.formatUtcDateTime(
              startAtTo!,
              field: 'SearchEventRequest.start_at_to',
            ),
      'start_date_from': startDateFrom,
      'start_date_to': startDateTo,
      'status': List<String>.unmodifiable(status),
      'category_ids': List<String>.unmodifiable(categoryIds),
      'importance': List<String>.unmodifiable(importance),
      'location': location,
      'has_recurrence': hasRecurrence,
      'source': List<String>.unmodifiable(source),
      'include_deleted': includeDeleted,
      'pagination': pagination.toJson(),
      'sort_by': sortBy,
      'sort_direction': sortDirection,
    };
  }
}
