class PaginationRequestDto {
  const PaginationRequestDto({
    this.page = 1,
    this.pageSize = 20,
    this.cursor,
    this.sortBy,
    this.sortDirection = 'desc',
  });

  final int? page;
  final int? pageSize;
  final String? cursor;
  final String? sortBy;
  final String? sortDirection;

  Map<String, dynamic> toJson() {
    if (page != null && page! < 1) {
      throw const FormatException('PaginationRequest.page must be positive.');
    }
    if (pageSize != null && (pageSize! < 1 || pageSize! > 200)) {
      throw const FormatException(
        'PaginationRequest.page_size must be between 1 and 200.',
      );
    }
    if (sortDirection != null &&
        sortDirection != 'asc' &&
        sortDirection != 'desc') {
      throw FormatException(
        'Unknown PaginationRequest.sort_direction: $sortDirection',
      );
    }
    return {
      'page': page,
      'page_size': pageSize,
      'cursor': cursor,
      'sort_by': sortBy,
      'sort_direction': sortDirection,
    };
  }
}
