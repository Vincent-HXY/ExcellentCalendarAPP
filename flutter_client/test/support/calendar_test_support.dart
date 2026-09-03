import 'package:excellent_calendar/gateway_interfaces/calendar_gateway.dart';
import 'package:excellent_calendar/native_contract/calendar/calendar_contract_enums.dart';
import 'package:excellent_calendar/native_contract/calendar/calendar_request_dtos.dart';
import 'package:excellent_calendar/native_contract/calendar/calendar_response_dtos.dart';

typedef CalendarRangeHandler =
    Future<CalendarRangeSummaryResponseDto> Function(
      CalendarRangeSummaryRequestDto request,
    );
typedef CalendarPageHandler =
    Future<CalendarDayItemPageDto> Function(
      CalendarListDayItemsRequestDto request,
    );

class CallbackCalendarGateway implements CalendarGateway {
  CallbackCalendarGateway({
    CalendarRangeHandler? onRange,
    CalendarPageHandler? onPage,
  }) : onRange =
           onRange ??
           ((request) async => calendarRangeResponse(request: request)),
       onPage =
           onPage ??
           ((request) async => calendarPageResponse(request: request));

  final CalendarRangeHandler onRange;
  final CalendarPageHandler onPage;
  final List<CalendarRangeSummaryRequestDto> rangeRequests = [];
  final List<CalendarListDayItemsRequestDto> pageRequests = [];

  @override
  Future<CalendarRangeSummaryResponseDto> rangeSummary(
    CalendarRangeSummaryRequestDto request,
  ) {
    rangeRequests.add(request);
    return onRange(request);
  }

  @override
  Future<CalendarDayItemPageDto> listDayItems(
    CalendarListDayItemsRequestDto request,
  ) {
    pageRequests.add(request);
    return onPage(request);
  }
}

const calendarTimezone = 'Asia/Shanghai';
const calendarSnapshotA = 'calsnap1.AAAAAAAAAAAAAAAAAAAA';
const calendarSnapshotB = 'calsnap1.BBBBBBBBBBBBBBBBBBBB';
const calendarSnapshotC = 'calsnap1.CCCCCCCCCCCCCCCCCCCC';
const calendarCursorA = 'calcur1.AAAAAAAAAAAAAAAAAAAA';
const calendarCursorB = 'calcur1.BBBBBBBBBBBBBBBBBBBB';

CalendarRangeSummaryResponseDto calendarRangeResponse({
  required CalendarRangeSummaryRequestDto request,
  String snapshotToken = calendarSnapshotA,
  bool hasOpenEvent = true,
  bool hasPendingHabit = true,
  bool hasAnniversary = true,
}) {
  final start = DateTime.parse('${request.rangeStartDate}T00:00:00Z');
  final end = DateTime.parse('${request.rangeEndDate}T00:00:00Z');
  return CalendarRangeSummaryResponseDto(
    rangeStartDate: request.rangeStartDate,
    rangeEndDate: request.rangeEndDate,
    timezone: request.timezone,
    snapshotToken: snapshotToken,
    days: [
      for (
        var date = start;
        date.isBefore(end);
        date = date.add(const Duration(days: 1))
      )
        CalendarRangeDaySummaryDto(
          date: formatCalendarTestDate(date),
          hasOpenEvent: hasOpenEvent,
          hasPendingHabit: hasPendingHabit,
          hasAnniversary: hasAnniversary,
        ),
    ],
  );
}

CalendarDayItemPageDto calendarPageResponse({
  required CalendarListDayItemsRequestDto request,
  String? snapshotToken,
  List<CalendarDayItemDto>? items,
  bool hasMore = false,
  String? nextCursor,
}) => CalendarDayItemPageDto(
  date: request.date,
  timezone: request.timezone,
  section: request.section,
  snapshotToken: snapshotToken ?? request.snapshotToken,
  pageSize: request.pageSize,
  items: items ?? calendarItemsFor(request.section, request.date),
  hasMore: hasMore,
  nextCursor: nextCursor,
);

List<CalendarDayItemDto> calendarItemsFor(
  CalendarSection section,
  String date, {
  int start = 1,
  int count = 1,
}) => [
  for (var index = start; index < start + count; index++)
    switch (section) {
      CalendarSection.event => calendarEvent(index),
      CalendarSection.habit => calendarHabit(index, date),
      CalendarSection.anniversary => calendarAnniversary(index, date),
    },
];

CalendarEventItemDto calendarEvent(int index) => CalendarEventItemDto(
  eventId: calendarUuid(index),
  title: '日程 $index',
  isAllDay: false,
  isRecurring: false,
  recurrenceRevision: null,
  occurrenceKey: null,
  occurrenceStartAt: null,
  occurrenceStartDate: null,
  startAt: DateTime.utc(2026, 8, 31, 1),
  endAt: DateTime.utc(2026, 8, 31, 2),
  startDate: null,
  endDate: null,
  dayDisplay: CalendarEventDayDisplay.startsAt,
  displayLocalTime: '09:00',
  status: CalendarEventItemStatus.pending,
  hasActiveReminder: true,
);

CalendarHabitItemDto calendarHabit(int index, String date) =>
    CalendarHabitItemDto(
      habitId: calendarUuid(index),
      date: date,
      title: '习惯 $index',
      status: CalendarHabitItemStatus.absent,
      checkInId: null,
      completedCountHundredths: null,
      targetCountHundredths: null,
      unit: null,
      hasActiveReminder: false,
    );

CalendarAnniversaryItemDto calendarAnniversary(int index, String date) =>
    CalendarAnniversaryItemDto(
      anniversaryId: calendarUuid(index),
      occurrenceKey: calendarUuid(index + 1000),
      occurrenceDate: date,
      sourceDate: '2020-08-31',
      title: '纪念日 $index',
      isRepeating: true,
      yearsElapsed: 6,
      importance: CalendarAnniversaryImportance.importantNotUrgent,
      hasActiveReminder: true,
    );

String calendarUuid(int value) {
  final suffix = value.toString().padLeft(12, '0');
  return '00000000-0000-4000-8000-$suffix';
}

String formatCalendarTestDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

Map<String, dynamic> calendarRangeJson(
  CalendarRangeSummaryRequestDto request, {
  String snapshotToken = calendarSnapshotA,
}) {
  final response = calendarRangeResponse(
    request: request,
    snapshotToken: snapshotToken,
  );
  return {
    'range_start_date': response.rangeStartDate,
    'range_end_date': response.rangeEndDate,
    'timezone': response.timezone,
    'snapshot_token': response.snapshotToken,
    'days': [
      for (final day in response.days)
        {
          'date': day.date,
          'has_open_event': day.hasOpenEvent,
          'has_pending_habit': day.hasPendingHabit,
          'has_anniversary': day.hasAnniversary,
        },
    ],
  };
}

Map<String, dynamic> calendarPageJson(
  CalendarListDayItemsRequestDto request, {
  String? snapshotToken,
}) => {
  'date': request.date,
  'timezone': request.timezone,
  'section': request.section.wireValue,
  'snapshot_token': snapshotToken ?? request.snapshotToken,
  'page_size': request.pageSize,
  'items': [calendarItemJson(request.section, request.date)],
  'has_more': false,
  'next_cursor': null,
};

Map<String, dynamic> calendarItemJson(CalendarSection section, String date) =>
    switch (section) {
      CalendarSection.event => {
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
      },
      CalendarSection.habit => {
        'habit_id': calendarUuid(2),
        'date': date,
        'title': '阅读',
        'status': 'absent',
        'check_in_id': null,
        'completed_count_hundredths': null,
        'target_count_hundredths': null,
        'unit': null,
        'has_active_reminder': false,
      },
      CalendarSection.anniversary => {
        'anniversary_id': calendarUuid(3),
        'occurrence_key': calendarUuid(1003),
        'occurrence_date': date,
        'source_date': '2020-08-31',
        'title': '入学纪念',
        'is_repeating': true,
        'years_elapsed': 6,
        'importance': 'important_noturgent',
        'has_active_reminder': true,
      },
    };
