import 'package:excellent_calendar/application/event/recurring_event_detail_controller.dart';
import 'package:excellent_calendar/application/event/update_event_use_case.dart';
import 'package:excellent_calendar/application/reminder/reconcile_reminder_schedule_use_case.dart';
import 'package:excellent_calendar/application/timezone/timezone_application_service.dart';
import 'package:excellent_calendar/data/category/fake_category_repository.dart';
import 'package:excellent_calendar/gateway_interfaces/event_native_gateway.dart';
import 'package:excellent_calendar/gateway_interfaces/reminder_native_gateway.dart';
import 'package:excellent_calendar/gateway_interfaces/timezone_native_gateway.dart';
import 'package:excellent_calendar/native_contract/event/event_detail_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_occurrence_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_occurrence_state_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_response_dto.dart';
import 'package:excellent_calendar/native_contract/recurrence/recurrence_response_dto.dart';
import 'package:excellent_calendar/native_contract/runtime/local_wall_date_time.dart';
import 'package:excellent_calendar/presentation/event_detail/pages/event_detail_flow_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'recurring detail renders original timezone rule and occurrence actions',
    (tester) async {
      final state = _readyState();
      final controller = _RecordingController(state);

      await tester.pumpWidget(
        MaterialApp(
          home: RecurringEventDetailPage(
            controller: controller,
            state: state,
            updateEventUseCase: UpdateEventUseCase(_UnusedEventGateway()),
            timezoneService: const TimezoneApplicationService(
              _UnusedTimezoneGateway(),
            ),
            categoryRepository: FakeCategoryRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('重复日程详情'), findsOneWidget);
      expect(find.text('月末财务检查'), findsOneWidget);
      expect(find.text('进行中'), findsOneWidget);
      expect(find.text('每月 · 31 日'), findsOneWidget);
      expect(find.text('Europe/London'), findsWidgets);
      expect(find.text('自动使用当月最后一天，锚点不变'), findsOneWidget);
      expect(find.text('通知定位'), findsOneWidget);

      final complete = find.byKey(
        const ValueKey('complete-occurrence-occ-scheduled'),
      );
      await tester.scrollUntilVisible(complete, 260);
      await tester.tap(complete);
      await tester.pump();
      expect(controller.completedOccurrenceKeys, ['occ-scheduled']);

      final more = find.byKey(const ValueKey('more-occurrence-occ-scheduled'));
      await tester.tap(more);
      await tester.pumpAndSettle();
      await tester.tap(find.text('跳过本次'));
      await tester.pumpAndSettle();
      expect(controller.skippedOccurrenceKeys, ['occ-scheduled']);

      await tester.tap(more);
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消本次'));
      await tester.pumpAndSettle();
      expect(find.text('取消本次日程？'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '取消本次'));
      await tester.pumpAndSettle();
      expect(controller.cancelledOccurrenceKeys, ['occ-scheduled']);

      final reopen = find.byKey(
        const ValueKey('reopen-occurrence-occ-completed'),
      );
      await tester.scrollUntilVisible(reopen, 220);
      await tester.tap(reopen);
      await tester.pump();
      expect(controller.reopenedOccurrenceKeys, ['occ-completed']);
    },
  );

  testWidgets('series management confirms whole-series completion', (
    tester,
  ) async {
    final state = _readyState();
    final controller = _RecordingController(state);
    await tester.pumpWidget(
      MaterialApp(
        home: RecurringEventDetailPage(
          controller: controller,
          state: state,
          updateEventUseCase: UpdateEventUseCase(_UnusedEventGateway()),
          timezoneService: const TimezoneApplicationService(
            _UnusedTimezoneGateway(),
          ),
          categoryRepository: FakeCategoryRepository(),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('manage-whole-series')));
    await tester.pumpAndSettle();
    expect(find.text('系列操作不会只作用于当前这一次'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('complete-series-action')));
    await tester.pumpAndSettle();
    expect(find.text('完成整个系列？'), findsOneWidget);
    expect(find.text('整个系列会停止继续提醒。你之后仍可重新打开系列。'), findsOneWidget);

    await tester.tap(find.text('完成系列'));
    await tester.pumpAndSettle();
    expect(controller.completeSeriesCalls, 1);
    expect(find.text('整个重复系列已完成'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('manage-whole-series')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cancel-series-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '取消系列'));
    await tester.pumpAndSettle();
    expect(controller.cancelSeriesCalls, 1);

    await tester.tap(find.byKey(const ValueKey('manage-whole-series')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-series-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除系列'));
    await tester.pumpAndSettle();
    expect(controller.deleteSeriesCalls, 1);
  });

  testWidgets('completed series can reopen from the current time forward', (
    tester,
  ) async {
    final state = _readyState(status: 'completed');
    final controller = _RecordingController(state);
    await tester.pumpWidget(
      MaterialApp(
        home: RecurringEventDetailPage(
          controller: controller,
          state: state,
          updateEventUseCase: UpdateEventUseCase(_UnusedEventGateway()),
          timezoneService: const TimezoneApplicationService(
            _UnusedTimezoneGateway(),
          ),
          categoryRepository: FakeCategoryRepository(),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('manage-whole-series')));
    await tester.pumpAndSettle();
    expect(find.text('从现在之后的第一个合法日程实例开始'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reopen-series-action')));
    await tester.pumpAndSettle();
    expect(find.textContaining('不会补发更早的提醒'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '重新打开'));
    await tester.pumpAndSettle();

    expect(controller.reopenSeriesCalls, 1);
  });

  testWidgets('recurring detail has no overflow on a narrow phone', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    final state = _readyState();

    await tester.pumpWidget(
      MaterialApp(
        home: RecurringEventDetailPage(
          controller: _RecordingController(state),
          state: state,
          updateEventUseCase: UpdateEventUseCase(_UnusedEventGateway()),
          timezoneService: const TimezoneApplicationService(
            _UnusedTimezoneGateway(),
          ),
          categoryRepository: FakeCategoryRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

RecurringEventDetailState _readyState({String status = 'active'}) {
  final event = EventResponseDto(
    id: 'event-recurring',
    title: '月末财务检查',
    content: '核对当月账目与预算。',
    startAt: DateTime.parse('2026-08-31T08:00:00Z'),
    endAt: DateTime.parse('2026-08-31T09:00:00Z'),
    startDate: null,
    endDate: null,
    isAllDay: false,
    hasRecurrence: true,
    status: status,
    recurrenceId: 'recurrence-1',
    recurrenceRevision: 4,
    timezone: 'Europe/London',
    source: 'manual',
    importance: 'important_noturgent',
    location: '书房',
    createdAt: DateTime.parse('2026-07-01T00:00:00Z'),
    updatedAt: DateTime.parse('2026-08-01T00:00:00Z'),
  );
  final recurrence = RecurrenceResponseDto(
    recurrenceId: 'recurrence-1',
    revision: 4,
    frequency: 'monthly',
    interval: 1,
    startAt: DateTime.parse('2026-08-31T08:00:00Z'),
    startDate: null,
    timezone: 'Europe/London',
    dayOfMonth: 31,
    daysOfWeek: const [],
    createdAt: DateTime.parse('2026-07-01T00:00:00Z'),
  );
  final scheduled = EventOccurrenceResponseDto(
    eventId: event.id,
    recurrenceRevision: 4,
    occurrenceKey: 'occ-scheduled',
    occurrenceStartAt: DateTime.parse('2026-08-31T08:00:00Z'),
    occurrenceEndAt: DateTime.parse('2026-08-31T09:00:00Z'),
    occurrenceStartDate: null,
    occurrenceEndDate: null,
    timezone: event.timezone,
    state: null,
  );
  final completed = EventOccurrenceResponseDto(
    eventId: event.id,
    recurrenceRevision: 4,
    occurrenceKey: 'occ-completed',
    occurrenceStartAt: DateTime.parse('2026-07-31T08:00:00Z'),
    occurrenceEndAt: DateTime.parse('2026-07-31T09:00:00Z'),
    occurrenceStartDate: null,
    occurrenceEndDate: null,
    timezone: event.timezone,
    state: EventOccurrenceStateResponseDto(
      eventId: event.id,
      recurrenceRevision: 4,
      occurrenceKey: 'occ-completed',
      occurrenceStartAt: DateTime.parse('2026-07-31T08:00:00Z'),
      occurrenceStartDate: null,
      status: 'completed',
      stateChangedAt: DateTime.parse('2026-07-31T10:00:00Z'),
      reopenedAt: null,
      createdAt: DateTime.parse('2026-07-31T10:00:00Z'),
      updatedAt: DateTime.parse('2026-07-31T10:00:00Z'),
    ),
  );
  return RecurringEventDetailState(
    phase: RecurringEventDetailPhase.ready,
    detail: EventDetailResponseDto(
      event: event,
      recurrence: recurrence,
      reminders: const [],
      category: null,
    ),
    localizedEventTimeRange: const LocalizedTimeRange(
      start: LocalWallDateTime(
        year: 2026,
        month: 8,
        day: 31,
        hour: 9,
        minute: 0,
        second: 0,
      ),
      end: LocalWallDateTime(
        year: 2026,
        month: 8,
        day: 31,
        hour: 10,
        minute: 0,
        second: 0,
      ),
      timezone: 'Europe/London',
    ),
    referenceLocalNow: const LocalWallDateTime(
      year: 2026,
      month: 8,
      day: 5,
      hour: 13,
      minute: 0,
      second: 0,
    ),
    occurrences: [
      RecurringEventOccurrenceItem(
        occurrence: scheduled,
        localizedTimeRange: const LocalizedTimeRange(
          start: LocalWallDateTime(
            year: 2026,
            month: 8,
            day: 31,
            hour: 9,
            minute: 0,
            second: 0,
          ),
          end: LocalWallDateTime(
            year: 2026,
            month: 8,
            day: 31,
            hour: 10,
            minute: 0,
            second: 0,
          ),
          timezone: 'Europe/London',
        ),
      ),
      RecurringEventOccurrenceItem(
        occurrence: completed,
        localizedTimeRange: const LocalizedTimeRange(
          start: LocalWallDateTime(
            year: 2026,
            month: 7,
            day: 31,
            hour: 9,
            minute: 0,
            second: 0,
          ),
          end: LocalWallDateTime(
            year: 2026,
            month: 7,
            day: 31,
            hour: 10,
            minute: 0,
            second: 0,
          ),
          timezone: 'Europe/London',
        ),
      ),
    ],
    hasMore: false,
    nextCursor: null,
    focusOccurrenceKey: 'occ-scheduled',
    isRefreshing: false,
    isLoadingMore: false,
    occurrenceMutations: const {},
    seriesMutation: null,
    isDeleted: false,
  );
}

class _RecordingController extends RecurringEventDetailController {
  _RecordingController(this.currentState)
    : super(
        eventId: currentState.detail!.event.id,
        gateway: _UnusedEventGateway(),
        timezoneService: const TimezoneApplicationService(
          _UnusedTimezoneGateway(),
        ),
        reconcileReminderScheduleUseCase: ReconcileReminderScheduleUseCase(
          _UnusedReminderGateway(),
        ),
      );

  final RecurringEventDetailState currentState;
  final completedOccurrenceKeys = <String>[];
  final reopenedOccurrenceKeys = <String>[];
  final skippedOccurrenceKeys = <String>[];
  final cancelledOccurrenceKeys = <String>[];
  var completeSeriesCalls = 0;
  var reopenSeriesCalls = 0;
  var cancelSeriesCalls = 0;
  var deleteSeriesCalls = 0;

  @override
  RecurringEventDetailState get state => currentState;

  @override
  Future<RecurringEventActionResult> completeOccurrence(String occurrenceKey) {
    completedOccurrenceKeys.add(occurrenceKey);
    return Future.value(const RecurringEventActionResult.success());
  }

  @override
  Future<RecurringEventActionResult> reopenOccurrence(String occurrenceKey) {
    reopenedOccurrenceKeys.add(occurrenceKey);
    return Future.value(const RecurringEventActionResult.success());
  }

  @override
  Future<RecurringEventActionResult> skipOccurrence(String occurrenceKey) {
    skippedOccurrenceKeys.add(occurrenceKey);
    return Future.value(const RecurringEventActionResult.success());
  }

  @override
  Future<RecurringEventActionResult> cancelOccurrence(String occurrenceKey) {
    cancelledOccurrenceKeys.add(occurrenceKey);
    return Future.value(const RecurringEventActionResult.success());
  }

  @override
  Future<RecurringEventActionResult> completeSeries() {
    completeSeriesCalls += 1;
    return Future.value(const RecurringEventActionResult.success());
  }

  @override
  Future<RecurringEventActionResult> reopenSeries() {
    reopenSeriesCalls += 1;
    return Future.value(const RecurringEventActionResult.success());
  }

  @override
  Future<RecurringEventActionResult> cancelSeries() {
    cancelSeriesCalls += 1;
    return Future.value(const RecurringEventActionResult.success());
  }

  @override
  Future<RecurringEventActionResult> deleteSeries({String? reason}) {
    deleteSeriesCalls += 1;
    return Future.value(const RecurringEventActionResult.success());
  }
}

class _UnusedEventGateway implements EventNativeGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedReminderGateway implements ReminderNativeGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedTimezoneGateway implements TimezoneNativeGateway {
  const _UnusedTimezoneGateway();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
