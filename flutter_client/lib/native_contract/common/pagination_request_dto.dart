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
    return {
      'page': page,
      'page_size': pageSize,
      'cursor': cursor,
      'sort_by': sortBy,
      'sort_direction': sortDirection,
    };
  }
}
