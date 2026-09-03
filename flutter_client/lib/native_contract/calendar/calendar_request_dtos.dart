import '../shared/contract_value.dart';
import 'calendar_civil_date.dart';
import 'calendar_contract_enums.dart';

final RegExp _calendarSnapshotPattern = RegExp(
  r'^calsnap1\.[A-Za-z0-9_-]{20,512}$',
);
final RegExp _calendarCursorPattern = RegExp(
  r'^calcur1\.[A-Za-z0-9_-]{20,2048}$',
);

class CalendarRangeSummaryRequestDto {
  CalendarRangeSummaryRequestDto({
    required this.rangeStartDate,
    required this.rangeEndDate,
    required this.timezone,
  }) {
    final start = CalendarCivilDate.parse(
      rangeStartDate,
      field: 'CalendarRangeSummaryRequest.range_start_date',
    );
    final end = CalendarCivilDate.parse(
      rangeEndDate,
      field: 'CalendarRangeSummaryRequest.range_end_date',
    );
    if (timezone.isEmpty || timezone.length > 255) {
      throw const FormatException(
        'CalendarRangeSummaryRequest.timezone must be 1..255 characters.',
      );
    }
    final days = start.daysUntil(end);
    if (days < 1 || days > 42) {
      throw const FormatException(
        'CalendarRangeSummaryRequest range must contain 1..42 natural days.',
      );
    }
  }

  final String rangeStartDate;
  final String rangeEndDate;
  final String timezone;

  Map<String, dynamic> toJson() => {
    'range_start_date': rangeStartDate,
    'range_end_date': rangeEndDate,
    'timezone': timezone,
  };
}

class CalendarListDayItemsRequestDto {
  CalendarListDayItemsRequestDto({
    required this.date,
    required this.timezone,
    required this.section,
    required this.snapshotToken,
    this.cursor,
    this.pageSize = 20,
  }) {
    ContractValue.validateLocalDate(
      date,
      field: 'CalendarListDayItemsRequest.date',
    );
    if (timezone.isEmpty || timezone.length > 255) {
      throw const FormatException(
        'CalendarListDayItemsRequest.timezone must be 1..255 characters.',
      );
    }
    if (!_calendarSnapshotPattern.hasMatch(snapshotToken) ||
        snapshotToken.length > 521) {
      throw const FormatException(
        'CalendarListDayItemsRequest.snapshot_token is malformed.',
      );
    }
    final value = cursor;
    if (value != null &&
        (!_calendarCursorPattern.hasMatch(value) || value.length > 2056)) {
      throw const FormatException(
        'CalendarListDayItemsRequest.cursor is malformed.',
      );
    }
    if (pageSize < 1 || pageSize > 100) {
      throw const FormatException(
        'CalendarListDayItemsRequest.page_size must be 1..100.',
      );
    }
  }

  final String date;
  final String timezone;
  final CalendarSection section;
  final String snapshotToken;
  final String? cursor;
  final int pageSize;

  Map<String, dynamic> toJson() => {
    'date': date,
    'timezone': timezone,
    'section': section.wireValue,
    'snapshot_token': snapshotToken,
    'cursor': cursor,
    'page_size': pageSize,
  };
}

bool isCalendarSnapshotToken(String value) =>
    value.length <= 521 && _calendarSnapshotPattern.hasMatch(value);

bool isCalendarCursor(String value) =>
    value.length <= 2056 && _calendarCursorPattern.hasMatch(value);
