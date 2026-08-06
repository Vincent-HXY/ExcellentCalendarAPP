import '../shared/contract_json_object.dart';

class PaginationResponseDto {
  const PaginationResponseDto({
    required this.total,
    required this.page,
    required this.pageSize,
    required this.hasMore,
    required this.nextCursor,
  });

  final int? total;
  final int? page;
  final int pageSize;
  final bool hasMore;
  final String? nextCursor;

  factory PaginationResponseDto.fromJson(Map<String, dynamic> json) {
    ContractJsonObject.rejectUnknownKeys(json, {
      'total',
      'page',
      'page_size',
      'has_more',
      'next_cursor',
    }, 'PaginationResponse');
    ContractJsonObject.requireKeys(json, {
      'total',
      'page',
      'page_size',
      'has_more',
      'next_cursor',
    }, 'PaginationResponse');

    return PaginationResponseDto(
      total: _readOptionalInt(json, 'total'),
      page: _readOptionalInt(json, 'page'),
      pageSize: _readInt(json, 'page_size'),
      hasMore: _readBool(json, 'has_more'),
      nextCursor: _readOptionalString(json, 'next_cursor'),
    );
  }

  static int _readInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) {
      return value;
    }
    throw FormatException('PaginationResponse.$key must be integer.');
  }

  static int? _readOptionalInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    throw FormatException('PaginationResponse.$key must be integer or null.');
  }

  static bool _readBool(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is bool) {
      return value;
    }
    throw FormatException('PaginationResponse.$key must be bool.');
  }

  static String? _readOptionalString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    throw FormatException('PaginationResponse.$key must be string or null.');
  }
}
