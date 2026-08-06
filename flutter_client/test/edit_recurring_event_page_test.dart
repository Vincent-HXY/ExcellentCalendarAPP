import 'dart:async';

import 'package:excellent_calendar/application/event/update_event_use_case.dart';
import 'package:excellent_calendar/application/timezone/timezone_application_service.dart';
import 'package:excellent_calendar/gateway_interfaces/event_native_gateway.dart';
import 'package:excellent_calendar/gateway_interfaces/timezone_native_gateway.dart';
import 'package:excellent_calendar/native_contract/common/native_error_dto.dart';
import 'package:excellent_calendar/native_contract/common/native_result_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_detail_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/update_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/recurrence/recurrence_response_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/reminder_contract_enums.dart';
import 'package:excellent_calendar/native_contract/reminder/reminder_response_dto.dart';
import 'package:excellent_calendar/native_contract/runtime/device_timezone_response_dto.dart';
import 'package:excellent_calendar/native_contract/runtime/local_wall_date_time.dart';
import 'package:excellent_calendar/native_contract/runtime/localize_instants_dto.dart';
import 'package:excellent_calendar/native_contract/runtime/resolve_local_datetime_dto.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';
import 'package:excellent_calendar/presentation/new_schedule/components/app_switch.dart';
import 'package:excellent_calendar/presentation/new_schedule/edit_recurring_event_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _eventId = '11111111-1111-4111-8111-111111111111';
const _recurrenceId = '22222222-2222-4222-8222-222222222222';

void main() {
  testWidgets(
    'updates title metadata recurrence and popup templates for the whole series',
    (tester) async {
      final detail = _detail(reminderAdvanceMinutes: const [15]);
      final eventGateway = _FakeEventGateway(event: detail.event);
      final timezoneGateway = _FakeTimezoneGateway();
      final result = ValueNotifier<bool?>(null);
      await _pumpEditor(
        tester,
        detail: detail,
        eventGateway: eventGateway,
        timezoneGateway: timezoneGateway,
        result: result,
      );

      expect(find.text('修改整个系列'), findsOneWidget);
      expect(find.textContaining('不支持仅修改本次'), findsOneWidget);
      expect(find.text('每天'), findsOneWidget);
      expect(find.text('15 分钟前'), findsOneWidget);
      expect(find.text('Europe/London'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'Updated stand-up');
      await tester.enterText(find.byType(TextField).at(1), 'Room 202');
      await tester.enterText(find.byType(TextField).at(2), 'Bring the report');

      await tester.ensureVisible(find.text('每天'));
      await tester.tap(find.text('每天'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('每月'));
      await tester.tap(find.text('确定').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('15 分钟前'));
      await tester.tap(find.text('15 分钟前'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15 分钟前').last);
      await tester.tap(find.text('30 分钟前').last);
      await tester.tap(find.text('确定').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('edit-series-save')));
      await tester.pumpAndSettle();

      expect(result.value, isTrue);
      expect(eventGateway.updateRequests, hasLength(1));
      final json = eventGateway.updateRequests.single.toJson();
      expect(json['id'], _eventId);
      expect(json['expected_recurrence_revision'], 3);
      expect(json['title'], 'Updated stand-up');
      expect(json['content'], 'Bring the report');
      expect(json['location'], 'Room 202');
      expect(json['recurrence'], {
        'frequency': 'monthly',
        'interval': 1,
        'end_at': null,
        'count': null,
      });
      expect(json['reminders'], [
        {
          'target_type': 'event',
          'target_id': null,
          'advance_minutes': 30,
          'methods': ['popup'],
          'message': null,
          'is_enabled': true,
          'source': 'manual',
        },
      ]);
      expect(json, isNot(contains('start_at')));
      expect(json, isNot(contains('timezone')));
    },
  );

  testWidgets(
    'all-day conversion first blocks existing reminders then sends an empty replacement',
    (tester) async {
      final detail = _detail(reminderAdvanceMinutes: const [15]);
      final eventGateway = _FakeEventGateway(event: detail.event);
      final timezoneGateway = _FakeTimezoneGateway();
      final result = ValueNotifier<bool?>(null);
      await _pumpEditor(
        tester,
        detail: detail,
        eventGateway: eventGateway,
        timezoneGateway: timezoneGateway,
        result: result,
      );

      final allDay = _allDaySwitch();
      await tester.ensureVisible(allDay);
      await tester.tap(allDay);
      await tester.pump();
      expect(find.textContaining('请先清空提醒'), findsOneWidget);

      await tester.ensureVisible(find.text('15 分钟前'));
      await tester.tap(find.text('15 分钟前'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15 分钟前').last);
      await tester.tap(find.text('确定').last);
      await tester.pumpAndSettle();
      expect(find.text('不提醒'), findsOneWidget);

      await tester.ensureVisible(allDay);
      await tester.tap(allDay);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('edit-series-save')));
      await tester.pumpAndSettle();

      expect(result.value, isTrue);
      final json = eventGateway.updateRequests.single.toJson();
      expect(json['is_all_day'], isTrue);
      expect(json['start_at'], isNull);
      expect(json['end_at'], isNull);
      expect(json['start_date'], '2026-03-28');
      expect(json['end_date'], '2026-03-29');
      expect(json['timezone'], 'Europe/London');
      expect(json['reminders'], isEmpty);
      expect(timezoneGateway.resolveRequests, isEmpty);
      expect(timezoneGateway.deviceTimezoneReadCount, 0);
    },
  );

  testWidgets('yearly custom and once choices cannot replace the series rule', (
    tester,
  ) async {
    final detail = _detail();
    final eventGateway = _FakeEventGateway(event: detail.event);
    final timezoneGateway = _FakeTimezoneGateway();
    await _pumpEditor(
      tester,
      detail: detail,
      eventGateway: eventGateway,
      timezoneGateway: timezoneGateway,
      result: ValueNotifier<bool?>(null),
    );

    await tester.ensureVisible(find.text('每天'));
    await tester.tap(find.text('每天'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -280));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每年'));
    await tester.pump();
    expect(find.text('每年重复暂未开放'), findsOneWidget);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('每天'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -280));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('自定义重复规则暂未开放'), findsOneWidget);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('每天'), findsOneWidget);

    await tester.tap(find.text('每天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仅一次'));
    await tester.tap(find.text('确定').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('重复系列本期不能改为仅一次日程'), findsOneWidget);
    expect(find.text('每天'), findsOneWidget);
    expect(eventGateway.updateRequests, isEmpty);
  });

  testWidgets(
    'London DST gap adjusts the wall time and requires a second save',
    (tester) async {
      final detail = _detail(
        startAt: DateTime.parse('2026-03-29T00:30:00Z'),
        endAt: DateTime.parse('2026-03-29T02:00:00Z'),
      );
      final eventGateway = _FakeEventGateway(event: detail.event);
      final timezoneGateway = _FakeTimezoneGateway(
        localize: (_) => [
          LocalWallDateTime.parse('2026-03-29T01:30:00'),
          LocalWallDateTime.parse('2026-03-29T03:00:00'),
        ],
        resolve: (request) {
          if (request.localDateTime.toString() == '2026-03-29T01:30:00') {
            return ResolveLocalDateTimeResponseDto(
              requestedLocalDateTime: request.localDateTime,
              resolvedLocalDateTime: LocalWallDateTime.parse(
                '2026-03-29T02:00:00',
              ),
              utcInstant: DateTime.parse('2026-03-29T01:00:00Z'),
              timezone: request.timezone,
              resolution: LocalDateTimeResolution.gapShifted,
            );
          }
          return _exactResolution(
            request,
            utcInstant: DateTime.utc(
              request.localDateTime.year,
              request.localDateTime.month,
              request.localDateTime.day,
              request.localDateTime.hour - 1,
              request.localDateTime.minute,
            ),
          );
        },
      );
      final result = ValueNotifier<bool?>(null);
      await _pumpEditor(
        tester,
        detail: detail,
        eventGateway: eventGateway,
        timezoneGateway: timezoneGateway,
        result: result,
      );

      await _markTimeChanged(tester);
      await tester.tap(find.byKey(const ValueKey('edit-series-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(eventGateway.updateRequests, isEmpty);
      expect(find.textContaining('夏令时跳时区间'), findsOneWidget);
      expect(find.text('02:00'), findsOneWidget);
      expect(
        timezoneGateway.resolveRequests.every(
          (request) => request.timezone == 'Europe/London',
        ),
        isTrue,
      );
      expect(timezoneGateway.deviceTimezoneReadCount, 0);

      await tester.tap(find.byKey(const ValueKey('edit-series-save')));
      await tester.pumpAndSettle();
      expect(result.value, isTrue);
      expect(eventGateway.updateRequests, hasLength(1));
    },
  );

  testWidgets('London DST fold submits the earlier UTC instant', (
    tester,
  ) async {
    final detail = _detail(
      startAt: DateTime.parse('2026-10-25T00:30:00Z'),
      endAt: DateTime.parse('2026-10-25T02:30:00Z'),
    );
    final eventGateway = _FakeEventGateway(event: detail.event);
    final timezoneGateway = _FakeTimezoneGateway(
      localize: (_) => [
        LocalWallDateTime.parse('2026-10-25T01:30:00'),
        LocalWallDateTime.parse('2026-10-25T02:30:00'),
      ],
      resolve: (request) {
        if (request.localDateTime.toString() == '2026-10-25T01:30:00') {
          return ResolveLocalDateTimeResponseDto(
            requestedLocalDateTime: request.localDateTime,
            resolvedLocalDateTime: request.localDateTime,
            utcInstant: DateTime.parse('2026-10-25T00:30:00Z'),
            timezone: request.timezone,
            resolution: LocalDateTimeResolution.foldEarlier,
          );
        }
        return _exactResolution(
          request,
          utcInstant: DateTime.parse('2026-10-25T02:30:00Z'),
        );
      },
    );
    final result = ValueNotifier<bool?>(null);
    await _pumpEditor(
      tester,
      detail: detail,
      eventGateway: eventGateway,
      timezoneGateway: timezoneGateway,
      result: result,
    );

    await _markTimeChanged(tester);
    await tester.tap(find.byKey(const ValueKey('edit-series-save')));
    await tester.pumpAndSettle();

    expect(result.value, isTrue);
    final json = eventGateway.updateRequests.single.toJson();
    expect(json['start_at'], '2026-10-25T00:30:00Z');
    expect(json['end_at'], '2026-10-25T02:30:00Z');
    expect(json['timezone'], 'Europe/London');
    expect(timezoneGateway.deviceTimezoneReadCount, 0);
  });

  testWidgets('duplicate save is ignored while the first update is pending', (
    tester,
  ) async {
    final detail = _detail();
    final pending = Completer<NativeInvocation<EventResponseDto>>();
    final eventGateway = _FakeEventGateway(
      event: detail.event,
      pendingUpdate: pending,
    );
    final result = ValueNotifier<bool?>(null);
    await _pumpEditor(
      tester,
      detail: detail,
      eventGateway: eventGateway,
      timezoneGateway: _FakeTimezoneGateway(),
      result: result,
    );

    final save = find.byKey(const ValueKey('edit-series-save'));
    await tester.tap(save);
    await tester.tap(save);
    await tester.pump();

    expect(eventGateway.updateRequests, hasLength(1));
    expect(find.text('保存中'), findsOneWidget);
    pending.complete(_success(detail.event));
    await tester.pumpAndSettle();
    expect(result.value, isTrue);
  });

  testWidgets('native failure keeps every user input for retry', (
    tester,
  ) async {
    final detail = _detail();
    final eventGateway = _FakeEventGateway(
      event: detail.event,
      failuresRemaining: 1,
    );
    await _pumpEditor(
      tester,
      detail: detail,
      eventGateway: eventGateway,
      timezoneGateway: _FakeTimezoneGateway(),
      result: ValueNotifier<bool?>(null),
    );

    await tester.enterText(find.byType(TextField).at(0), 'Keep this title');
    await tester.enterText(find.byType(TextField).at(1), 'Keep this place');
    await tester.enterText(find.byType(TextField).at(2), 'Keep this note');
    await tester.tap(find.byKey(const ValueKey('edit-series-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.textContaining('RECURRENCE_REVISION_CONFLICT'), findsOneWidget);
    expect(find.text('Keep this title'), findsOneWidget);
    expect(find.text('Keep this place'), findsOneWidget);
    expect(find.text('Keep this note'), findsOneWidget);
    expect(find.byType(EditRecurringEventPage), findsOneWidget);
  });

  testWidgets('time localization failure has a retry path', (tester) async {
    final detail = _detail();
    final timezoneGateway = _FakeTimezoneGateway(localizeFailuresRemaining: 1);
    await _pumpEditor(
      tester,
      detail: detail,
      eventGateway: _FakeEventGateway(event: detail.event),
      timezoneGateway: timezoneGateway,
      result: ValueNotifier<bool?>(null),
      settle: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Timezone unavailable.'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('Daily stand-up'), findsOneWidget);
    expect(timezoneGateway.localizeRequests, hasLength(2));
  });

  testWidgets('reminders from an older recurrence revision are not templates', (
    tester,
  ) async {
    final detail = _detail(
      reminderAdvanceMinutes: const [15],
      reminderRecurrenceRevision: 2,
    );
    await _pumpEditor(
      tester,
      detail: detail,
      eventGateway: _FakeEventGateway(event: detail.event),
      timezoneGateway: _FakeTimezoneGateway(),
      result: ValueNotifier<bool?>(null),
    );

    await tester.ensureVisible(find.text('不提醒'));
    expect(find.text('不提醒'), findsOneWidget);
  });

  testWidgets('cancel returns false without updating', (tester) async {
    final detail = _detail();
    final eventGateway = _FakeEventGateway(event: detail.event);
    final result = ValueNotifier<bool?>(null);
    await _pumpEditor(
      tester,
      detail: detail,
      eventGateway: eventGateway,
      timezoneGateway: _FakeTimezoneGateway(),
      result: result,
    );

    await tester.tap(find.byKey(const ValueKey('edit-series-cancel')));
    await tester.pumpAndSettle();
    expect(result.value, isFalse);
    expect(eventGateway.updateRequests, isEmpty);
  });
}

Future<void> _markTimeChanged(WidgetTester tester) async {
  final allDay = _allDaySwitch();
  await tester.ensureVisible(allDay);
  await tester.tap(allDay);
  await tester.pump();
  await tester.tap(allDay);
  await tester.pump();
}

Finder _allDaySwitch() => find.byWidgetPredicate(
  (widget) => widget is AppSwitch && widget.semanticLabel == '全天',
);

Future<void> _pumpEditor(
  WidgetTester tester, {
  required EventDetailResponseDto detail,
  required _FakeEventGateway eventGateway,
  required _FakeTimezoneGateway timezoneGateway,
  required ValueNotifier<bool?> result,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: _EditorLauncher(
        detail: detail,
        updateUseCase: UpdateEventUseCase(eventGateway),
        timezoneService: TimezoneApplicationService(timezoneGateway),
        onResult: (value) => result.value = value,
      ),
    ),
  );
  await tester.tap(find.text('打开编辑页'));
  await tester.pump();
  if (settle) await tester.pumpAndSettle();
}

class _EditorLauncher extends StatelessWidget {
  const _EditorLauncher({
    required this.detail,
    required this.updateUseCase,
    required this.timezoneService,
    required this.onResult,
  });

  final EventDetailResponseDto detail;
  final UpdateEventUseCase updateUseCase;
  final TimezoneApplicationService timezoneService;
  final ValueChanged<bool?> onResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () async {
            final result = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (context) => EditRecurringEventPage(
                  detail: detail,
                  updateUseCase: updateUseCase,
                  timezoneService: timezoneService,
                ),
              ),
            );
            onResult(result);
          },
          child: const Text('打开编辑页'),
        ),
      ),
    );
  }
}

class _FakeEventGateway implements EventNativeGateway {
  _FakeEventGateway({
    required this.event,
    this.failuresRemaining = 0,
    this.pendingUpdate,
  });

  final EventResponseDto event;
  int failuresRemaining;
  final Completer<NativeInvocation<EventResponseDto>>? pendingUpdate;
  final List<UpdateEventRequestDto> updateRequests = [];

  @override
  Future<NativeInvocation<EventResponseDto>> updateEvent(
    UpdateEventRequestDto request,
  ) async {
    updateRequests.add(request);
    if (pendingUpdate != null) return pendingUpdate!.future;
    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      return _failure<EventResponseDto>(
        code: 'RECURRENCE_REVISION_CONFLICT',
        message: 'The series changed on another screen.',
      );
    }
    return _success(event);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

typedef _LocalizeFake =
    List<LocalWallDateTime> Function(LocalizeInstantsRequestDto request);
typedef _ResolveFake =
    ResolveLocalDateTimeResponseDto Function(
      ResolveLocalDateTimeRequestDto request,
    );

class _FakeTimezoneGateway implements TimezoneNativeGateway {
  _FakeTimezoneGateway({
    this.localize,
    this.resolve,
    this.localizeFailuresRemaining = 0,
  });

  final _LocalizeFake? localize;
  final _ResolveFake? resolve;
  int localizeFailuresRemaining;
  int deviceTimezoneReadCount = 0;
  final List<LocalizeInstantsRequestDto> localizeRequests = [];
  final List<ResolveLocalDateTimeRequestDto> resolveRequests = [];

  @override
  Future<NativeInvocation<DeviceTimezoneResponseDto>>
  getDeviceTimezone() async {
    deviceTimezoneReadCount += 1;
    return _success(const DeviceTimezoneResponseDto(timezone: 'Asia/Shanghai'));
  }

  @override
  Future<NativeInvocation<LocalizeInstantsResponseDto>> localizeInstants(
    LocalizeInstantsRequestDto request,
  ) async {
    localizeRequests.add(request);
    if (localizeFailuresRemaining > 0) {
      localizeFailuresRemaining -= 1;
      return _failure<LocalizeInstantsResponseDto>(
        code: 'INVALID_TIMEZONE',
        message: 'Timezone unavailable.',
      );
    }
    final walls =
        localize?.call(request) ??
        request.instants
            .map(LocalWallDateTime.fromDateTimeComponents)
            .toList(growable: false);
    return _success(
      LocalizeInstantsResponseDto(
        timezone: request.timezone,
        items: List.generate(
          request.instants.length,
          (index) => LocalizedInstantDto(
            instant: request.instants[index],
            localDateTime: walls[index],
          ),
          growable: false,
        ),
      ),
    );
  }

  @override
  Future<NativeInvocation<ResolveLocalDateTimeResponseDto>>
  resolveLocalDateTime(ResolveLocalDateTimeRequestDto request) async {
    resolveRequests.add(request);
    return _success(resolve?.call(request) ?? _exactResolution(request));
  }
}

ResolveLocalDateTimeResponseDto _exactResolution(
  ResolveLocalDateTimeRequestDto request, {
  DateTime? utcInstant,
}) {
  return ResolveLocalDateTimeResponseDto(
    requestedLocalDateTime: request.localDateTime,
    resolvedLocalDateTime: request.localDateTime,
    utcInstant:
        utcInstant ??
        DateTime.utc(
          request.localDateTime.year,
          request.localDateTime.month,
          request.localDateTime.day,
          request.localDateTime.hour,
          request.localDateTime.minute,
          request.localDateTime.second,
        ),
    timezone: request.timezone,
    resolution: LocalDateTimeResolution.exact,
  );
}

NativeInvocation<T> _success<T>(T data) {
  return NativeInvocation<T>(
    rawResponse: const {},
    result: NativeResultDto<T>(
      ok: true,
      data: data,
      error: null,
      contractVersion: 2,
      requestId: 'test-request',
    ),
    isNativeResult: true,
  );
}

NativeInvocation<T> _failure<T>({
  required String code,
  required String message,
}) {
  return NativeInvocation<T>(
    rawResponse: const {},
    result: NativeResultDto<T>(
      ok: false,
      data: null,
      error: NativeErrorDto(code: code, message: message, retryable: true),
      contractVersion: 2,
      requestId: 'test-failure',
    ),
    isNativeResult: true,
  );
}

EventDetailResponseDto _detail({
  bool isAllDay = false,
  List<int> reminderAdvanceMinutes = const [],
  DateTime? startAt,
  DateTime? endAt,
  String frequency = 'daily',
  int reminderRecurrenceRevision = 3,
}) {
  final actualStartAt = startAt ?? DateTime.parse('2026-03-28T09:00:00Z');
  final actualEndAt = endAt ?? DateTime.parse('2026-03-28T10:00:00Z');
  final event = EventResponseDto(
    id: _eventId,
    title: 'Daily stand-up',
    content: 'Original note',
    startAt: isAllDay ? null : actualStartAt,
    endAt: isAllDay ? null : actualEndAt,
    startDate: isAllDay ? '2026-03-28' : null,
    endDate: isAllDay ? '2026-03-29' : null,
    isAllDay: isAllDay,
    hasRecurrence: true,
    status: 'active',
    recurrenceId: _recurrenceId,
    recurrenceRevision: 3,
    timezone: 'Europe/London',
    source: 'manual',
    createdAt: DateTime.parse('2026-03-01T00:00:00Z'),
    updatedAt: DateTime.parse('2026-03-20T00:00:00Z'),
    location: 'Room 101',
  );
  final recurrence = RecurrenceResponseDto(
    recurrenceId: _recurrenceId,
    revision: 3,
    frequency: frequency,
    interval: 1,
    startAt: isAllDay ? null : actualStartAt,
    startDate: isAllDay ? '2026-03-28' : null,
    timezone: 'Europe/London',
    dayOfMonth: frequency == 'monthly' ? 28 : null,
    daysOfWeek: frequency == 'weekly' ? const [6] : const [],
    createdAt: DateTime.parse('2026-03-01T00:00:00Z'),
  );
  return EventDetailResponseDto(
    event: event,
    recurrence: recurrence,
    reminders: [
      for (var index = 0; index < reminderAdvanceMinutes.length; index++)
        ReminderResponseDto(
          reminderId:
              '44444444-4444-4444-8444-${(index + 1).toString().padLeft(12, '0')}',
          targetType: ReminderTargetType.event,
          targetId: _eventId,
          recurrenceRevision: reminderRecurrenceRevision,
          occurrenceKey: '33333333-3333-4333-8333-333333333333',
          occurrenceStartAt: actualStartAt,
          remindAt: actualStartAt.subtract(
            Duration(minutes: reminderAdvanceMinutes[index]),
          ),
          methods: const [ReminderMethod.popup],
          advanceMinutes: reminderAdvanceMinutes[index],
          isEnabled: true,
          status: ReminderStatus.scheduled,
          reactivationCount: 0,
          createdAt: DateTime.parse('2026-03-01T00:00:00Z'),
          updatedAt: DateTime.parse('2026-03-20T00:00:00Z'),
        ),
    ],
    category: null,
  );
}
