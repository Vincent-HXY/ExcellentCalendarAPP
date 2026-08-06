import '../common/pagination_request_dto.dart';

class SearchEventRequestDto {
  const SearchEventRequestDto({
    this.keyword,
    this.startAtFrom,
    this.startAtTo,
    this.status = const [],
    this.categoryIds = const [],
    this.importance = const [],
    this.location,
    this.hasRecurrence,
    this.source = const [],
    this.includeDeleted = false,
    this.pagination = const PaginationRequestDto(),
    this.sortBy = 'start_at',
    this.sortDirection = 'asc',
  });

  final String? keyword;
  final DateTime? startAtFrom;
  final DateTime? startAtTo;
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
      _validateStatus(value);
    }
    for (final value in importance) {
      _validateImportance(value);
    }
    for (final value in source) {
      _validateSource(value);
    }
    _validateSortBy(sortBy);
    _validateSortDirection(sortDirection);
    return {
      'keyword': keyword,
      'start_at_from': startAtFrom?.toUtc().toIso8601String(),
      'start_at_to': startAtTo?.toUtc().toIso8601String(),
      'status': status,
      'category_ids': categoryIds,
      'importance': importance,
      'location': location,
      'has_recurrence': hasRecurrence,
      'source': source,
      'include_deleted': includeDeleted,
      'pagination': pagination.toJson(),
      'sort_by': sortBy,
      'sort_direction': sortDirection,
    };
  }

  static void _validateStatus(String value) {
    const allowed = {'active', 'completed', 'cancelled', 'archived'};
    if (!allowed.contains(value)) {
      throw FormatException('Unknown EventStatus: $value');
    }
  }

  static void _validateImportance(String value) {
    const allowed = {
      'unimportant_noturgent',
      'important_noturgent',
      'unimportant_urgent',
      'important_urgent',
    };
    if (!allowed.contains(value)) {
      throw FormatException('Unknown Importance: $value');
    }
  }

  static void _validateSource(String value) {
    const allowed = {'manual', 'ai_extraction', 'sync', 'import', 'wechat'};
    if (!allowed.contains(value)) {
      throw FormatException('Unknown SearchEvent source: $value');
    }
  }

  static void _validateSortBy(String? value) {
    const allowed = {
      null,
      'start_at',
      'created_at',
      'updated_at',
      'importance',
      'title',
    };
    if (!allowed.contains(value)) {
      throw FormatException('Unknown SearchEvent sort_by: $value');
    }
  }

  static void _validateSortDirection(String? value) {
    const allowed = {null, 'asc', 'desc'};
    if (!allowed.contains(value)) {
      throw FormatException('Unknown SortDirection: $value');
    }
  }
}
