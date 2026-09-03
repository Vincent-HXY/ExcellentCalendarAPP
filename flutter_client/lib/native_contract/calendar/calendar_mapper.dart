import '../shared/native_json_normalizer.dart';
import 'calendar_response_dtos.dart';

abstract final class CalendarMapper {
  static CalendarRangeSummaryResponseDto rangeSummary(Object? raw) =>
      CalendarRangeSummaryResponseDto.fromJson(
        NativeJsonNormalizer.normalizeMap(raw),
      );

  static CalendarDayItemPageDto dayItemPage(Object? raw) =>
      CalendarDayItemPageDto.fromJson(NativeJsonNormalizer.normalizeMap(raw));
}
