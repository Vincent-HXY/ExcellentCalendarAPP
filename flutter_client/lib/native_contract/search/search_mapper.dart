import '../shared/native_json_normalizer.dart';
import 'search_response_dtos.dart';

abstract final class SearchMapper {
  static SearchQueryResponseDto query(Object? raw) =>
      SearchQueryResponseDto.fromJson(NativeJsonNormalizer.normalizeMap(raw));

  static SearchHistoryResponseDto history(Object? raw) =>
      SearchHistoryResponseDto.fromJson(NativeJsonNormalizer.normalizeMap(raw));
}
