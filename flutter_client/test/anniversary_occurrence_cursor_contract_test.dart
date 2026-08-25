import 'package:excellent_calendar/native_contract/anniversary/anniversary_request_dtos.dart';
import 'package:excellent_calendar/native_contract/anniversary/anniversary_response_dtos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'C++ golden cursor passes the response DTO and the next-page request DTO',
    () {
      final response = AnniversaryOccurrenceListResponseDto.fromJson({
        'items': [_occurrence],
        'has_more': true,
        'next_cursor': _cppGoldenCursor,
      });

      final nextPage = _request(response.nextCursor).toJson();

      expect(response.nextCursor, _cppGoldenCursor);
      expect(nextPage['cursor'], _cppGoldenCursor);
    },
  );

  test('legacy dotted generation fails both response and request DTOs', () {
    expect(
      () => AnniversaryOccurrenceListResponseDto.fromJson({
        'items': [_occurrence],
        'has_more': true,
        'next_cursor': _legacyDottedGenerationCursor,
      }),
      throwsFormatException,
    );
    expect(
      () => _request(_legacyDottedGenerationCursor).toJson(),
      throwsFormatException,
    );
  });
}

ListAnniversaryOccurrencesRequestDto _request(String? cursor) =>
    ListAnniversaryOccurrencesRequestDto(
      rangeStartDate: DateTime(2026, 8, 1),
      rangeEndDate: DateTime(2027, 9, 5),
      timezone: 'Asia/Shanghai',
      categoryIds: const [],
      importance: const [],
      cursor: cursor,
      pageSize: 50,
    );

const _cppGoldenCursor =
    'annocc1.60f0df06-830c-52d2-a659-e8848aa200cd_3-1-1_55ed42b28911a7e6';
const _legacyDottedGenerationCursor =
    'annocc1.60f0df06-830c-52d2-a659-e8848aa200cd_3.1.1_55ed42b28911a7e6';

const _occurrence = <String, Object?>{
  'anniversary_id': '22222222-2222-4222-8222-222222222222',
  'occurrence_key': '11111111-1111-4111-8111-111111111111',
  'occurrence_date': '2026-09-01',
  'source_date': '2020-09-01',
  'title': 'C++ cursor fixture',
  'calendar_type': 'solar',
  'is_repeating': true,
  'years_elapsed': 6,
  'category_id': null,
  'importance': null,
  'has_active_reminders': false,
  'reminder_count': 0,
};
