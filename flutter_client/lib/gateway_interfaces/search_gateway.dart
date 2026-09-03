import '../native_contract/search/search_request_dtos.dart';
import '../native_contract/search/search_response_dtos.dart';

abstract interface class SearchGateway {
  Future<SearchQueryResponseDto> query(SearchQueryRequestDto request);
}

class SearchGatewayFailure implements Exception {
  const SearchGatewayFailure({
    required this.code,
    required this.message,
    required this.retryable,
    this.details,
  });
  final String code;
  final String message;
  final bool retryable;
  final Map<String, dynamic>? details;

  bool get isCursorExpired => code == 'SEARCH_CURSOR_EXPIRED';
  bool get isHistoryConflict => code == 'SEARCH_HISTORY_CONFLICT';

  @override
  String toString() => 'SearchGatewayFailure($code, $message)';
}
