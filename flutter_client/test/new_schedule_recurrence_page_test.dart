import 'dart:async';

import 'package:excellent_calendar/application/event/create_event_use_case.dart';
import 'package:excellent_calendar/application/timezone/timezone_application_service.dart';
import 'package:excellent_calendar/gateway_interfaces/event_native_gateway.dart';
import 'package:excellent_calendar/native_contract/common/native_result_dto.dart';
import 'package:excellent_calendar/native_contract/event/create_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_response_dto.dart';
import 'package:excellent_calendar/native_contract/runtime/local_wall_date_time.dart';
import 'package:excellent_calendar/native_contract/runtime/resolve_local_datetime_dto.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';
import 'package:excellent_calendar/presentation/new_schedule/components/app_switch.dart';
import 'package:excellent_calendar/presentation/new_schedule/components/time_range_card.dart';
import 'package:excellent_calendar/presentation/new_schedule/date_time_picker/calendar_date_panel.dart';
import 'package:excellent_calendar/presentation/new_schedule/new_schedule_page.dart';
import 'package:excellent_calendar/presentation/new_schedule/selection/floating_selection_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_timezone_gateway.dart';

void main() {
  const supportedRecurrences = {'每天': 'daily', '每周': 'weekly', '每月': 'monthly'};

  for (final recurrence in supportedRecurrences.entries) {
    testWidgets('${recurrence.key}提交最小 recurrence intent 和 popup advance 模板', (
      tester,
    ) async {
      final gateway = _RecordingEventGateway();
      await _pumpPage(
        tester,
        eventGateway: gateway,
        timezoneGateway: FakeTimezoneGateway(),
      );

      await _enterTitle(tester, '${recurrence.key}复盘');
      await _chooseSupportedRecurrence(tester, recurrence.key);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();

      expect(gateway.createRequests, hasLength(1));
      final request = gateway.createRequests.single;
      final json = request.toJson();
      expect(json['recurrence'], {
        'frequency': recurrence.value,
        'interval': 1,
        'end_at': null,
        'count': null,
      });
      expect(
        (json['recurrence'] as Map<String, dynamic>).keys,
        isNot(
          containsAll(<String>[
            'start_at',
            'timezone',
            'day_of_month',
            'days_of_week',
            'month_of_year',
          ]),
        ),
      );
      expect(json['reminders'], [
        {
          'target_type': 'event',
          'target_id': null,
          'advance_minutes': 15,
          'methods': ['popup'],
          'message': null,
          'is_enabled': true,
          'source': 'manual',
        },
      ]);
      expect(
        (json['reminders'] as List<dynamic>).single,
        isNot(contains('remind_at')),
      );
    });
  }

  const unsupportedRecurrences = {'每年': '每年重复暂未开放', '自定义': '自定义重复规则后续实现'};

  for (final recurrence in unsupportedRecurrences.entries) {
    testWidgets('${recurrence.key}显示暂未开放且不提交', (tester) async {
      final gateway = _RecordingEventGateway();
      await _pumpPage(
        tester,
        eventGateway: gateway,
        timezoneGateway: FakeTimezoneGateway(),
      );

      await _openRecurrenceSheet(tester);
      final sheet = find.byType(FloatingSelectionSheet);
      final option = await _visibleSheetOption(
        tester,
        sheet: sheet,
        label: recurrence.key,
      );
      await tester.tap(option);
      await tester.pumpAndSettle();

      expect(find.text(recurrence.value), findsOneWidget);
      expect(gateway.createRequests, isEmpty);

      await tester.tap(find.descendant(of: sheet, matching: find.text('取消')));
      await tester.pumpAndSettle();
      expect(find.text('仅一次'), findsOneWidget);
    });
  }

  testWidgets('连续点击完成只创建一次重复日程', (tester) async {
    final pendingCreate = Completer<NativeInvocation<EventResponseDto>>();
    final gateway = _RecordingEventGateway(
      onCreate: (_) => pendingCreate.future,
    );
    await _pumpPage(
      tester,
      eventGateway: gateway,
      timezoneGateway: FakeTimezoneGateway(),
    );
    await _enterTitle(tester, '避免重复创建');
    await _chooseSupportedRecurrence(tester, '每天');

    final submit = find.text('完成');
    await tester.tap(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(gateway.createRequests, hasLength(1));
    expect(find.text('保存中'), findsOneWidget);

    pendingCreate.complete(
      _successfulCreateInvocation(gateway.createRequests.single),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('全天 Event 保留提醒并阻止选择重复规则', (tester) async {
    final gateway = _RecordingEventGateway();
    await _pumpPage(
      tester,
      eventGateway: gateway,
      timezoneGateway: FakeTimezoneGateway(),
    );

    await tester.tap(find.byType(AppSwitch).first);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TimeRangeCard>(find.byType(TimeRangeCard)).isAllDay,
      isTrue,
    );

    await _chooseSupportedRecurrence(tester, '每天');

    expect(find.text('全天重复日程暂不支持提醒'), findsOneWidget);
    expect(find.text('仅一次'), findsOneWidget);
    expect(find.text('15 分钟前'), findsOneWidget);
    expect(gateway.createRequests, isEmpty);
  });

  testWidgets('London DST gap 首次保存只调整时间且不创建', (tester) async {
    final gateway = _RecordingEventGateway();
    final timezoneGateway = FakeTimezoneGateway(
      deviceTimezones: const ['Europe/London'],
      resolve: (request) {
        if (request.localDateTime ==
            const LocalWallDateTime(
              year: 2026,
              month: 3,
              day: 29,
              hour: 1,
              minute: 30,
              second: 0,
            )) {
          return ResolveLocalDateTimeResponseDto(
            requestedLocalDateTime: request.localDateTime,
            resolvedLocalDateTime: const LocalWallDateTime(
              year: 2026,
              month: 3,
              day: 29,
              hour: 2,
              minute: 0,
              second: 0,
            ),
            utcInstant: DateTime.utc(2026, 3, 29, 1),
            timezone: request.timezone,
            resolution: LocalDateTimeResolution.gapShifted,
          );
        }
        if (request.localDateTime ==
            const LocalWallDateTime(
              year: 2026,
              month: 3,
              day: 29,
              hour: 2,
              minute: 30,
              second: 0,
            )) {
          return ResolveLocalDateTimeResponseDto(
            requestedLocalDateTime: request.localDateTime,
            resolvedLocalDateTime: request.localDateTime,
            utcInstant: DateTime.utc(2026, 3, 29, 1, 30),
            timezone: request.timezone,
            resolution: LocalDateTimeResolution.exact,
          );
        }
        throw StateError('Unexpected London gap request: ${request.toJson()}');
      },
    );
    await _pumpPage(
      tester,
      eventGateway: gateway,
      timezoneGateway: timezoneGateway,
    );
    await _enterTitle(tester, 'London 跳时会议');
    await _selectDateTime(
      tester,
      start: true,
      value: DateTime(2026, 3, 29, 1, 30),
    );
    await _selectDateTime(
      tester,
      start: false,
      value: DateTime(2026, 3, 29, 2, 30),
    );
    await _chooseSupportedRecurrence(tester, '每天');

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(gateway.createRequests, isEmpty);
    expect(find.text('所选时间落在夏令时跳时区间，已移到首个合法时间，请确认后再次保存'), findsOneWidget);
    final adjusted = tester.widget<TimeRangeCard>(find.byType(TimeRangeCard));
    expect(adjusted.startAt, DateTime.utc(2026, 3, 29, 2));
    expect(adjusted.endAt, DateTime.utc(2026, 3, 29, 2, 30));
  });

  testWidgets('London DST fold 提交第一次出现对应的较早 UTC Instant', (tester) async {
    final gateway = _RecordingEventGateway();
    final timezoneGateway = FakeTimezoneGateway(
      deviceTimezones: const ['Europe/London'],
      resolve: (request) {
        if (request.localDateTime ==
            const LocalWallDateTime(
              year: 2026,
              month: 10,
              day: 25,
              hour: 1,
              minute: 30,
              second: 0,
            )) {
          return ResolveLocalDateTimeResponseDto(
            requestedLocalDateTime: request.localDateTime,
            resolvedLocalDateTime: request.localDateTime,
            utcInstant: DateTime.utc(2026, 10, 25, 0, 30),
            timezone: request.timezone,
            resolution: LocalDateTimeResolution.foldEarlier,
          );
        }
        if (request.localDateTime ==
            const LocalWallDateTime(
              year: 2026,
              month: 10,
              day: 25,
              hour: 2,
              minute: 30,
              second: 0,
            )) {
          return ResolveLocalDateTimeResponseDto(
            requestedLocalDateTime: request.localDateTime,
            resolvedLocalDateTime: request.localDateTime,
            utcInstant: DateTime.utc(2026, 10, 25, 2, 30),
            timezone: request.timezone,
            resolution: LocalDateTimeResolution.exact,
          );
        }
        throw StateError('Unexpected London fold request: ${request.toJson()}');
      },
    );
    await _pumpPage(
      tester,
      eventGateway: gateway,
      timezoneGateway: timezoneGateway,
    );
    await _enterTitle(tester, 'London 回拨会议');
    await _selectDateTime(
      tester,
      start: true,
      value: DateTime(2026, 10, 25, 1, 30),
    );
    await _selectDateTime(
      tester,
      start: false,
      value: DateTime(2026, 10, 25, 2, 30),
    );
    await _chooseSupportedRecurrence(tester, '每天');

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(gateway.createRequests, hasLength(1));
    final request = gateway.createRequests.single;
    expect(request.timezone, 'Europe/London');
    expect(request.startAt, DateTime.utc(2026, 10, 25, 0, 30));
    expect(request.endAt, DateTime.utc(2026, 10, 25, 2, 30));
    expect(request.recurrence?.frequency, 'daily');
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _RecordingEventGateway eventGateway,
  required FakeTimezoneGateway timezoneGateway,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        );
      },
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return Center(
              child: TextButton(
                key: const ValueKey('open-new-schedule'),
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => NewSchedulePage(
                        createUseCase: CreateEventUseCase(eventGateway),
                        timezoneService: TimezoneApplicationService(
                          timezoneGateway,
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('新建日程'),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-new-schedule')));
  await tester.pumpAndSettle();
  expect(find.byType(NewSchedulePage), findsOneWidget);
}

Future<void> _enterTitle(WidgetTester tester, String title) async {
  await tester.enterText(find.byType(TextField).first, title);
  await tester.pump();
}

Future<void> _openRecurrenceSheet(WidgetTester tester) async {
  final recurrenceValue = find.text('仅一次');
  await tester.ensureVisible(recurrenceValue);
  await tester.tap(recurrenceValue);
  await tester.pumpAndSettle();
  expect(find.byType(FloatingSelectionSheet), findsOneWidget);
}

Future<void> _chooseSupportedRecurrence(
  WidgetTester tester,
  String label,
) async {
  await _openRecurrenceSheet(tester);
  final sheet = find.byType(FloatingSelectionSheet);
  final option = await _visibleSheetOption(tester, sheet: sheet, label: label);
  await tester.tap(option);
  await tester.pump();
  await tester.tap(find.descendant(of: sheet, matching: find.text('确定')));
  await tester.pumpAndSettle();
}

Future<void> _selectDateTime(
  WidgetTester tester, {
  required bool start,
  required DateTime value,
}) async {
  final range = tester.widget<TimeRangeCard>(find.byType(TimeRangeCard));
  final current = start ? range.startAt : range.endAt;
  final matchingDateText = find.text(_formDate(current));
  final dateText = start ? matchingDateText.first : matchingDateText.last;
  await tester.ensureVisible(dateText);
  await tester.tap(dateText);
  await tester.pumpAndSettle();

  final initialVisibleMonth = tester
      .widget<CalendarMonthHeader>(find.byType(CalendarMonthHeader))
      .visibleMonth;
  final monthDelta =
      (value.year - initialVisibleMonth.year) * 12 +
      value.month -
      initialVisibleMonth.month;
  final monthIcon = monthDelta >= 0
      ? Icons.chevron_right_rounded
      : Icons.chevron_left_rounded;
  final monthNavigation = find.descendant(
    of: find.byType(CalendarMonthHeader),
    matching: find.byIcon(monthIcon),
  );
  for (var index = 0; index < monthDelta.abs(); index++) {
    await tester.tap(monthNavigation);
    await tester.pumpAndSettle();
  }

  final day = find.descendant(
    of: find.byType(CalendarDayGrid),
    matching: find.text('${value.day}'),
  );
  expect(day, findsOneWidget);
  await Scrollable.ensureVisible(
    tester.element(day),
    alignment: 0.5,
    duration: Duration.zero,
  );
  await tester.pump();
  await tester.tap(day);
  await tester.pumpAndSettle();

  _jumpLoopingWheel(tester, wheel: 0, itemCount: 24, value: value.hour);
  await tester.pump();
  _jumpLoopingWheel(tester, wheel: 1, itemCount: 60, value: value.minute);
  await tester.pump();

  await tester.tap(find.text('确定'));
  await tester.pumpAndSettle();
}

Future<Finder> _visibleSheetOption(
  WidgetTester tester, {
  required Finder sheet,
  required String label,
}) async {
  final option = find.descendant(of: sheet, matching: find.text(label));
  await Scrollable.ensureVisible(
    tester.element(option),
    alignment: 0.5,
    duration: Duration.zero,
  );
  await tester.pump();
  return option;
}

void _jumpLoopingWheel(
  WidgetTester tester, {
  required int wheel,
  required int itemCount,
  required int value,
}) {
  final widget = tester.widget<ListWheelScrollView>(
    find.byType(ListWheelScrollView).at(wheel),
  );
  final controller = widget.controller! as FixedExtentScrollController;
  final currentRawIndex = controller.selectedItem;
  controller.jumpToItem(
    currentRawIndex - (currentRawIndex % itemCount) + value,
  );
}

String _formDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}/$month/$day';
}

typedef _CreateHandler =
    Future<NativeInvocation<EventResponseDto>> Function(
      CreateEventRequestDto request,
    );

class _RecordingEventGateway implements EventNativeGateway {
  _RecordingEventGateway({this.onCreate});

  final _CreateHandler? onCreate;
  final List<CreateEventRequestDto> createRequests = [];

  @override
  Future<NativeInvocation<EventResponseDto>> createEvent(
    CreateEventRequestDto request,
  ) {
    createRequests.add(request);
    return onCreate?.call(request) ??
        Future.value(_successfulCreateInvocation(request));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

NativeInvocation<EventResponseDto> _successfulCreateInvocation(
  CreateEventRequestDto request,
) {
  final hasRecurrence = request.recurrence != null;
  final event = EventResponseDto(
    id: 'event-created',
    title: request.title,
    content: request.content,
    startAt: request.startAt,
    endAt: request.endAt,
    startDate: request.startDate,
    endDate: request.endDate,
    isAllDay: request.isAllDay,
    hasRecurrence: hasRecurrence,
    status: 'active',
    recurrenceId: hasRecurrence ? 'recurrence-created' : null,
    recurrenceRevision: hasRecurrence ? 1 : null,
    categoryId: request.categoryId,
    importance: request.importance,
    location: request.location,
    timezone: request.timezone,
    source: request.source,
    createdAt: DateTime.utc(2026, 8, 5, 8),
    updatedAt: DateTime.utc(2026, 8, 5, 8),
  );
  return NativeInvocation<EventResponseDto>(
    rawResponse: const {},
    result: NativeResultDto<EventResponseDto>(
      ok: true,
      data: event,
      error: null,
      contractVersion: 2,
      requestId: 'create-request',
    ),
    isNativeResult: true,
  );
}
