import 'package:excellent_calendar/native_contract/calendar/calendar_contract_enums.dart';
import 'package:excellent_calendar/native_contract/calendar/calendar_request_dtos.dart';
import 'package:excellent_calendar/native_contract/calendar/calendar_response_dtos.dart';
import 'package:excellent_calendar/native_contract/common/native_result_dto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/calendar_test_support.dart';

void main() {
  group('Calendar request contract', () {
    test('serializes the frozen snake_case payloads', () {
      expect(
        CalendarRangeSummaryRequestDto(
          rangeStartDate: '2026-08-31',
          rangeEndDate: '2026-09-07',
          timezone: calendarTimezone,
        ).toJson(),
        {
          'range_start_date': '2026-08-31',
          'range_end_date': '2026-09-07',
          'timezone': calendarTimezone,
        },
      );
      expect(
        CalendarListDayItemsRequestDto(
          date: '2026-08-31',
          timezone: calendarTimezone,
          section: CalendarSection.event,
          snapshotToken: calendarSnapshotA,
          cursor: calendarCursorA,
        ).toJson(),
        {
          'date': '2026-08-31',
          'timezone': calendarTimezone,
          'section': 'event',
          'snapshot_token': calendarSnapshotA,
          'cursor': calendarCursorA,
          'page_size': 20,
        },
      );
    });

    test('rejects invalid natural ranges, tokens, cursors and page sizes', () {
      expect(
        () => CalendarRangeSummaryRequestDto(
          rangeStartDate: '2026-08-31',
          rangeEndDate: '2026-08-31',
          timezone: calendarTimezone,
        ),
        throwsFormatException,
      );
      expect(
        () => CalendarRangeSummaryRequestDto(
          rangeStartDate: '2026-08-31',
          rangeEndDate: '2026-10-13',
          timezone: calendarTimezone,
        ),
        throwsFormatException,
      );
      expect(
        () => CalendarListDayItemsRequestDto(
          date: '2026-08-31',
          timezone: calendarTimezone,
          section: CalendarSection.event,
          snapshotToken: 'not-a-token',
        ),
        throwsFormatException,
      );
      expect(
        () => CalendarListDayItemsRequestDto(
          date: '2026-08-31',
          timezone: calendarTimezone,
          section: CalendarSection.event,
          snapshotToken: calendarSnapshotA,
          cursor: 'not-a-cursor',
        ),
        throwsFormatException,
      );
      expect(
        () => CalendarListDayItemsRequestDto(
          date: '2026-08-31',
          timezone: calendarTimezone,
          section: CalendarSection.event,
          snapshotToken: calendarSnapshotA,
          pageSize: 101,
        ),
        throwsFormatException,
      );
    });
  });

  group('Calendar response contract', () {
    test('accepts one strict typed item in every section', () {
      final event = CalendarDayItemPageDto.fromJson(
        _pageJson('event', [_eventJson()]),
      );
      final habit = CalendarDayItemPageDto.fromJson(
        _pageJson('habit', [_habitJson()]),
      );
      final anniversary = CalendarDayItemPageDto.fromJson(
        _pageJson('anniversary', [_anniversaryJson()]),
      );

      expect(event.items.single, isA<CalendarEventItemDto>());
      expect(habit.items.single, isA<CalendarHabitItemDto>());
      expect(anniversary.items.single, isA<CalendarAnniversaryItemDto>());
    });

    test('enforces frozen quantitative Habit progress relationships', () {
      Map<String, dynamic> quantitativeHabit({
        required String status,
        required int completed,
        required int target,
      }) => _habitJson()
        ..['status'] = status
        ..['check_in_id'] = calendarUuid(4)
        ..['completed_count_hundredths'] = completed
        ..['target_count_hundredths'] = target
        ..['unit'] = '页';

      for (final invalid in [
        quantitativeHabit(status: 'partial', completed: 100, target: 100),
        quantitativeHabit(status: 'partial', completed: 101, target: 100),
        quantitativeHabit(status: 'done', completed: 99, target: 100),
      ]) {
        expect(
          () => CalendarHabitItemDto.fromJson(invalid),
          throwsFormatException,
        );
      }

      for (final valid in [
        quantitativeHabit(status: 'done', completed: 100, target: 100),
        quantitativeHabit(status: 'done', completed: 150, target: 100),
        _habitJson()
          ..['status'] = 'done'
          ..['check_in_id'] = calendarUuid(4),
      ]) {
        expect(() => CalendarHabitItemDto.fromJson(valid), returnsNormally);
      }
    });

    test('counts Habit title and unit limits as Unicode code points', () {
      Map<String, dynamic> habitWithText({
        required String title,
        String? unit,
      }) => _habitJson()
        ..['title'] = title
        ..['target_count_hundredths'] = unit == null ? null : 100
        ..['unit'] = unit;

      expect(
        () => CalendarHabitItemDto.fromJson(habitWithText(title: '📘' * 80)),
        returnsNormally,
      );
      expect(
        () => CalendarHabitItemDto.fromJson(habitWithText(title: '📘' * 81)),
        throwsFormatException,
      );
      expect(
        () => CalendarHabitItemDto.fromJson(
          habitWithText(title: '阅读', unit: '📖' * 32),
        ),
        returnsNormally,
      );
      expect(
        () => CalendarHabitItemDto.fromJson(
          habitWithText(title: '阅读', unit: '📖' * 33),
        ),
        throwsFormatException,
      );
    });

    test('requires timed and all-day Event starts to precede ends', () {
      final validTimed = _eventJson();
      final invalidTimed = _eventJson()
        ..['start_at'] = '2026-08-31T02:00:00Z'
        ..['end_at'] = '2026-08-31T02:00:00Z';
      final validAllDay = _allDayEventJson();
      final invalidAllDay = _allDayEventJson()
        ..['start_date'] = '2026-09-01'
        ..['end_date'] = '2026-09-01';

      for (final valid in [validTimed, validAllDay]) {
        expect(() => CalendarEventItemDto.fromJson(valid), returnsNormally);
      }
      for (final invalid in [invalidTimed, invalidAllDay]) {
        expect(
          () => CalendarEventItemDto.fromJson(invalid),
          throwsFormatException,
        );
      }
    });

    test('range is exact, gap-free, ascending and request-bound', () {
      final response = CalendarRangeSummaryResponseDto.fromJson(_rangeJson());
      final request = CalendarRangeSummaryRequestDto(
        rangeStartDate: '2026-08-31',
        rangeEndDate: '2026-09-02',
        timezone: calendarTimezone,
      );

      expect(response.days.map((day) => day.date), [
        '2026-08-31',
        '2026-09-01',
      ]);
      expect(() => response.validateAgainst(request), returnsNormally);

      final gap = _rangeJson();
      ((gap['days']! as List)[1] as Map<String, dynamic>)['date'] =
          '2026-09-02';
      expect(
        () => CalendarRangeSummaryResponseDto.fromJson(gap),
        throwsFormatException,
      );
      expect(
        () => response.validateAgainst(
          CalendarRangeSummaryRequestDto(
            rangeStartDate: '2026-08-31',
            rangeEndDate: '2026-09-02',
            timezone: 'UTC',
          ),
        ),
        throwsFormatException,
      );
    });

    test(
      'uses host-independent civil dates across Los Angeles DST boundaries',
      () {
        const scenarios = [
          (
            label: 'spring-forward',
            start: '2026-02-15',
            end42: '2026-03-29',
            end43: '2026-03-30',
          ),
          (
            label: 'fall-back',
            start: '2026-10-04',
            end42: '2026-11-15',
            end43: '2026-11-16',
          ),
        ];

        for (final scenario in scenarios) {
          expect(
            () => CalendarRangeSummaryRequestDto(
              rangeStartDate: scenario.start,
              rangeEndDate: scenario.end42,
              timezone: 'America/Los_Angeles',
            ),
            returnsNormally,
            reason: scenario.label,
          );
          expect(
            () => CalendarRangeSummaryRequestDto(
              rangeStartDate: scenario.start,
              rangeEndDate: scenario.end43,
              timezone: 'America/Los_Angeles',
            ),
            throwsFormatException,
            reason: scenario.label,
          );

          final validResponse = _rangeJsonFor(
            start: scenario.start,
            end: scenario.end42,
            timezone: 'America/Los_Angeles',
          );
          expect(
            () => CalendarRangeSummaryResponseDto.fromJson(validResponse),
            returnsNormally,
            reason: scenario.label,
          );

          final gapResponse = _rangeJsonFor(
            start: scenario.start,
            end: scenario.end42,
            timezone: 'America/Los_Angeles',
          );
          final days = gapResponse['days']! as List<Map<String, dynamic>>;
          days[21] = Map<String, dynamic>.from(days[22]);
          expect(
            () => CalendarRangeSummaryResponseDto.fromJson(gapResponse),
            throwsFormatException,
            reason: scenario.label,
          );
        }
      },
    );

    test('rejects unknown, missing, null and inconsistent item fields', () {
      final unknown = _eventJson()..['future'] = true;
      final missing = _eventJson()..remove('title');
      final nullRequired = _eventJson()..['title'] = null;
      final unknownEnum = _eventJson()..['status'] = 'paused';
      final inconsistent = _eventJson()
        ..['is_all_day'] = true
        ..['start_date'] = '2026-08-31'
        ..['end_date'] = '2026-09-01';

      for (final item in [
        unknown,
        missing,
        nullRequired,
        unknownEnum,
        inconsistent,
      ]) {
        expect(
          () => CalendarDayItemPageDto.fromJson(_pageJson('event', [item])),
          throwsFormatException,
        );
      }
    });

    test(
      'rejects section/date mismatch, duplicate identity and bad cursor',
      () {
        expect(
          () => CalendarDayItemPageDto.fromJson(
            _pageJson('habit', [_habitJson(date: '2026-09-01')]),
          ),
          throwsFormatException,
        );
        expect(
          () => CalendarDayItemPageDto.fromJson(
            _pageJson('habit', [_habitJson(), _habitJson()]),
          ),
          throwsFormatException,
        );
        expect(
          () => CalendarDayItemPageDto.fromJson(
            _pageJson('event', [_eventJson()], hasMore: true, nextCursor: null),
          ),
          throwsFormatException,
        );
        expect(
          () => CalendarDayItemPageDto.fromJson(
            _pageJson(
              'event',
              [_eventJson()],
              hasMore: false,
              nextCursor: calendarCursorA,
            ),
          ),
          throwsFormatException,
        );
      },
    );

    test('NativeResult rejects version drift and malformed success branch', () {
      expect(
        () => NativeResultDto<CalendarRangeSummaryResponseDto>.fromJson(
          {
            'ok': true,
            'data': _rangeJson(),
            'error': null,
            'contract_version': 3,
          },
          (raw) => CalendarRangeSummaryResponseDto.fromJson(
            raw! as Map<String, dynamic>,
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => NativeResultDto<CalendarRangeSummaryResponseDto>.fromJson(
          {'ok': true, 'data': null, 'error': null, 'contract_version': 2},
          (raw) => CalendarRangeSummaryResponseDto.fromJson(
            raw! as Map<String, dynamic>,
          ),
        ),
        throwsA(anyOf(isA<TypeError>(), isA<FormatException>())),
      );
    });
  });
}

Map<String, dynamic> _rangeJson() => {
  'range_start_date': '2026-08-31',
  'range_end_date': '2026-09-02',
  'timezone': calendarTimezone,
  'snapshot_token': calendarSnapshotA,
  'days': [_daySummary('2026-08-31'), _daySummary('2026-09-01')],
};

Map<String, dynamic> _rangeJsonFor({
  required String start,
  required String end,
  required String timezone,
}) {
  final startParts = start.split('-').map(int.parse).toList(growable: false);
  final endParts = end.split('-').map(int.parse).toList(growable: false);
  final startCoordinate = DateTime.utc(
    startParts[0],
    startParts[1],
    startParts[2],
  );
  final endCoordinate = DateTime.utc(endParts[0], endParts[1], endParts[2]);
  final count = endCoordinate.difference(startCoordinate).inDays;
  final days = List<Map<String, dynamic>>.generate(count, (index) {
    final date = startCoordinate.add(Duration(days: index));
    return _daySummary(
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}',
    );
  });
  return {
    'range_start_date': start,
    'range_end_date': end,
    'timezone': timezone,
    'snapshot_token': calendarSnapshotA,
    'days': days,
  };
}

Map<String, dynamic> _daySummary(String date) => {
  'date': date,
  'has_open_event': true,
  'has_pending_habit': true,
  'has_anniversary': true,
};

Map<String, dynamic> _pageJson(
  String section,
  List<Map<String, dynamic>> items, {
  bool hasMore = false,
  String? nextCursor,
}) => {
  'date': '2026-08-31',
  'timezone': calendarTimezone,
  'section': section,
  'snapshot_token': calendarSnapshotA,
  'page_size': 20,
  'items': items,
  'has_more': hasMore,
  'next_cursor': nextCursor,
};

Map<String, dynamic> _eventJson() => {
  'event_id': calendarUuid(1),
  'title': '会议',
  'is_all_day': false,
  'is_recurring': false,
  'recurrence_revision': null,
  'occurrence_key': null,
  'occurrence_start_at': null,
  'occurrence_start_date': null,
  'start_at': '2026-08-31T01:00:00Z',
  'end_at': '2026-08-31T02:00:00Z',
  'start_date': null,
  'end_date': null,
  'day_display': 'starts_at',
  'display_local_time': '09:00',
  'status': 'pending',
  'has_active_reminder': true,
};

Map<String, dynamic> _allDayEventJson() => _eventJson()
  ..['is_all_day'] = true
  ..['start_at'] = null
  ..['end_at'] = null
  ..['start_date'] = '2026-08-31'
  ..['end_date'] = '2026-09-01'
  ..['day_display'] = 'all_day'
  ..['display_local_time'] = null;

Map<String, dynamic> _habitJson({String date = '2026-08-31'}) => {
  'habit_id': calendarUuid(2),
  'date': date,
  'title': '阅读',
  'status': 'absent',
  'check_in_id': null,
  'completed_count_hundredths': null,
  'target_count_hundredths': null,
  'unit': null,
  'has_active_reminder': false,
};

Map<String, dynamic> _anniversaryJson() => {
  'anniversary_id': calendarUuid(3),
  'occurrence_key': calendarUuid(1003),
  'occurrence_date': '2026-08-31',
  'source_date': '2020-08-31',
  'title': '入学纪念',
  'is_repeating': true,
  'years_elapsed': 6,
  'importance': 'important_noturgent',
  'has_active_reminder': true,
};
