import '../native_contract/search/search_request_dtos.dart';
import '../native_contract/search/search_response_dtos.dart';

abstract interface class SearchHistoryGateway {
  Future<SearchHistoryResponseDto> getLocalHistory();
  Future<SearchHistoryResponseDto> replaceLocalHistory(
    ReplaceSearchHistoryRequestDto request,
  );
}
