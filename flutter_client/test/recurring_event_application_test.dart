import 'dart:async';

import 'package:excellent_calendar/application/event/recurring_event_detail_controller.dart';
import 'package:excellent_calendar/application/reminder/reconcile_reminder_schedule_use_case.dart';
import 'package:excellent_calendar/application/timezone/timezone_application_service.dart';
import 'package:excellent_calendar/gateway_interfaces/event_native_gateway.dart';
import 'package:excellent_calendar/gateway_interfaces/timezone_native_gateway.dart';
import 'package:excellent_calendar/native_contract/common/native_error_dto.dart';
import 'package:excellent_calendar/native_contract/common/native_result_dto.dart';
import 'package:excellent_calendar/native_contract/event/complete_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/create_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/delete_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_detail_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_list_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_occurrence_list_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_occurrence_operation_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_occurrence_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_occurrence_state_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_series_operation_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/get_event_detail_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/list_event_occurrences_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/reopen_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/search_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/update_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/recurrence/recurrence_response_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/reconcile_reminder_schedule_dto.dart';
import 'package:excellent_calendar/native_contract/runtime/device_timezone_response_dto.dart';
import 'package:excellent_calendar/native_contract/runtime/local_wall_date_time.dart';
import 'package:excellent_calendar/native_contract/runtime/localize_instants_dto.dart';
import 'package:excellent_calendar/native_contract/runtime/resolve_local_datetime_dto.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.parse('2026-08-05T12:00:00Z');

  test(
    'non-recurring Event loads detail and original-timezone range without occurrence query',
    () async {
      final event = _timedEvent(recurring: false);
      final eventGateway = _FakeEventGateway()
        ..onGetDetail = (_) async => _success(_detail(event));
      final timezoneGateway = _FakeTimezoneGateway(
        localize: (_, instant) => _wallFromInstant(instant, hours: 1),
      );
      final controller = _controller(
        eventGateway: eventGateway,
        timezoneGateway: timezoneGateway,
        now: now,
      );

      await controller.load();

      expect(controller.state.phase, RecurringEventDetailPhase.ready);
      expect(controller.state.isRecurring, isFalse);
      expect(controller.state.occurrences, isEmpty);
      expect(eventGateway.listRequests, isEmpty);
      expect(
        controller.state.localizedEventTimeRange!.start.toString(),
        '2026-08-05T10:00:00',
      );
      expect(
        controller.state.referenceLocalNow.toString(),
        '2026-08-05T13:00:00',
      );
      expect(
        timezoneGateway.localizeRequests.every(
          (request) => request.timezone == event.timezone,
        ),
        isTrue,
      );
    },
  );

  test(
    'recurring timed Event uses detail revision, bounded UTC window, and original timezone localization',
    () async {
      final event = _timedEvent();
      final occurrence = _timedOccurrence(key: 'occ-1');
      final eventGateway = _FakeEventGateway();
      eventGateway.onGetDetail = (_) async => _success(_detail(event));
      eventGateway.onList = (_) async => _success(
        EventOccurrenceListResponseDto(
          items: [occurrence],
          hasMore: true,
          nextCursor: 'cursor-1',
        ),
      );
      final timezoneGateway = _FakeTimezoneGateway(
        localize: (_, instant) => _wallFromInstant(instant, hours: 1),
      );
      final controller = _controller(
        eventGateway: eventGateway,
        timezoneGateway: timezoneGateway,
        now: now,
        focusOccurrenceKey: 'occ-1',
      );

      await controller.load();

      final request = eventGateway.listRequests.single;
      expect(request.eventId, event.id);
      expect(request.recurrenceRevision, 7);
      expect(request.rangeStartAt, DateTime.parse('2026-07-29T12:00:00Z'));
      expect(request.rangeEndAt, DateTime.parse('2026-11-03T12:00:00Z'));
      expect(request.rangeStartDate, isNull);
      expect(controller.state.hasMore, isTrue);
      expect(controller.state.nextCursor, 'cursor-1');
      expect(controller.state.focusOccurrenceKey, 'occ-1');
      expect(controller.state.occurrences.single.occurrence, same(occurrence));
      expect(
        controller.state.occurrences.single.localizedTimeRange.start.hour,
        10,
      );
      expect(controller.state.referenceLocalNow!.hour, 13);
    },
  );

  test(
    'all-day occurrence window is derived from Event original-timezone local date',
    () async {
      final event = _allDayEvent();
      final eventGateway = _FakeEventGateway();
      eventGateway.onGetDetail = (_) async => _success(_detail(event));
      eventGateway.onList = (_) async => _success(
        EventOccurrenceListResponseDto(
          items: [_allDayOccurrence()],
          hasMore: false,
          nextCursor: null,
        ),
      );
      final timezoneGateway = _FakeTimezoneGateway(
        localize: (_, _) => LocalWallDateTime.parse('2026-08-06T00:30:00'),
      );
      final controller = _controller(
        eventGateway: eventGateway,
        timezoneGateway: timezoneGateway,
        now: now,
      );

      await controller.load();

      final request = eventGateway.listRequests.single;
      expect(request.isAllDay, isTrue);
      expect(request.rangeStartDate, '2026-07-30');
      expect(request.rangeEndDate, '2026-11-04');
      expect(request.rangeStartAt, isNull);
      expect(controller.state.referenceLocalNow!.day, 6);
      expect(
        controller.state.occurrences.single.localizedTimeRange.start.toString(),
        '2026-08-06T00:00:00',
      );
      expect(timezoneGateway.localizeRequests, hasLength(1));
      expect(timezoneGateway.localizeRequests.single.instants, [now]);
    },
  );

  test('pagination forwards Native cursor and appends the next page', () async {
    final event = _timedEvent();
    final eventGateway = _FakeEventGateway();
    eventGateway.onGetDetail = (_) async => _success(_detail(event));
    eventGateway.onList = (request) async {
      if (request.cursor == null) {
        return _success(
          EventOccurrenceListResponseDto(
            items: [_timedOccurrence(key: 'occ-1')],
            hasMore: true,
            nextCursor: 'cursor-1',
          ),
        );
      }
      return _success(
        EventOccurrenceListResponseDto(
          items: [
            _timedOccurrence(key: 'occ-2', start: '2026-08-06T09:00:00Z'),
          ],
          hasMore: false,
          nextCursor: null,
        ),
      );
    };
    final controller = _controller(
      eventGateway: eventGateway,
      timezoneGateway: _FakeTimezoneGateway(),
      now: now,
    );

    await controller.load();
    await controller.loadMore();
    await controller.loadMore();

    expect(eventGateway.listRequests, hasLength(2));
    expect(eventGateway.listRequests.last.cursor, 'cursor-1');
    expect(controller.state.occurrences.map((item) => item.occurrenceKey), [
      'occ-1',
      'occ-2',
    ]);
    expect(controller.state.hasMore, isFalse);
    expect(controller.state.isLoadingMore, isFalse);
  });

  test('late detail response cannot overwrite a newer refresh', () async {
    final first = Completer<NativeInvocation<EventDetailResponseDto>>();
    final second = Completer<NativeInvocation<EventDetailResponseDto>>();
    var detailCall = 0;
    final eventGateway = _FakeEventGateway()
      ..onGetDetail = (_) {
        detailCall += 1;
        return detailCall == 1 ? first.future : second.future;
      };
    final controller = _controller(
      eventGateway: eventGateway,
      timezoneGateway: _FakeTimezoneGateway(),
      now: now,
    );

    final firstLoad = controller.load();
    final refresh = controller.refresh();
    second.complete(
      _success(_detail(_timedEvent(recurring: false, title: 'new'))),
    );
    await refresh;
    first.complete(
      _success(_detail(_timedEvent(recurring: false, title: 'old'))),
    );
    await firstLoad;

    expect(controller.state.event!.title, 'new');
    expect(controller.state.phase, RecurringEventDetailPhase.ready);
  });

  for (final mutation in RecurringEventOccurrenceMutation.values) {
    test(
      '${mutation.name} occurrence sends frozen identity, updates only the row, and reconciles',
      () async {
        final initialStatus =
            mutation == RecurringEventOccurrenceMutation.reopen
            ? 'completed'
            : 'scheduled';
        final occurrence = _timedOccurrence(
          key: 'occ-1',
          state: initialStatus == 'scheduled'
              ? null
              : _occurrenceState(status: initialStatus),
        );
        final expectedStatus = switch (mutation) {
          RecurringEventOccurrenceMutation.complete => 'completed',
          RecurringEventOccurrenceMutation.reopen => 'scheduled',
          RecurringEventOccurrenceMutation.skip => 'skipped',
          RecurringEventOccurrenceMutation.cancel => 'cancelled',
        };
        final eventGateway = _FakeEventGateway();
        eventGateway.onGetDetail = (_) async =>
            _success(_detail(_timedEvent()));
        eventGateway.onList = (_) async => _success(
          EventOccurrenceListResponseDto(
            items: [occurrence],
            hasMore: false,
            nextCursor: null,
          ),
        );
        eventGateway.onOccurrence = (_, _) async =>
            _success(_occurrenceState(status: expectedStatus));
        final reconcile = _FakeReconcileUseCase();
        final controller = _controller(
          eventGateway: eventGateway,
          timezoneGateway: _FakeTimezoneGateway(),
          reconcile: reconcile,
          now: now,
        );
        await controller.load();

        final result = await switch (mutation) {
          RecurringEventOccurrenceMutation.complete =>
            controller.completeOccurrence('occ-1'),
          RecurringEventOccurrenceMutation.reopen =>
            controller.reopenOccurrence('occ-1'),
          RecurringEventOccurrenceMutation.skip => controller.skipOccurrence(
            'occ-1',
          ),
          RecurringEventOccurrenceMutation.cancel =>
            controller.cancelOccurrence('occ-1'),
        };

        expect(result.succeeded, isTrue);
        expect(controller.state.occurrences.single.status, expectedStatus);
        expect(eventGateway.occurrenceCalls.single.$1, mutation);
        expect(eventGateway.occurrenceCalls.single.$2.toJson(), {
          'event_id': 'event-1',
          'recurrence_revision': 7,
          'occurrence_key': 'occ-1',
          'occurrence_start_at': '2026-08-05T09:00:00Z',
          'occurrence_start_date': null,
        });
        expect(reconcile.requests, hasLength(1));
        expect(
          reconcile.requests.single.triggerSource,
          ReminderScheduleTrigger.mutation,
        );
        expect(reconcile.requests.single.force, isTrue);
        expect(controller.state.occurrenceMutations, isEmpty);
      },
    );
  }

  test(
    'duplicate occurrence submission is ignored while first is pending',
    () async {
      final completer =
          Completer<NativeInvocation<EventOccurrenceStateResponseDto>>();
      final eventGateway = _FakeEventGateway();
      eventGateway.onGetDetail = (_) async => _success(_detail(_timedEvent()));
      eventGateway.onList = (_) async => _success(
        EventOccurrenceListResponseDto(
          items: [_timedOccurrence(key: 'occ-1')],
          hasMore: false,
          nextCursor: null,
        ),
      );
      eventGateway.onOccurrence = (_, _) => completer.future;
      final controller = _controller(
        eventGateway: eventGateway,
        timezoneGateway: _FakeTimezoneGateway(),
        now: now,
      );
      await controller.load();

      final first = controller.completeOccurrence('occ-1');
      final duplicate = await controller.completeOccurrence('occ-1');

      expect(duplicate.wasIgnored, isTrue);
      expect(eventGateway.occurrenceCalls, hasLength(1));
      completer.complete(_success(_occurrenceState(status: 'completed')));
      expect((await first).succeeded, isTrue);
    },
  );

  test(
    'Native occurrence failure preserves business state and does not reconcile',
    () async {
      final eventGateway = _FakeEventGateway();
      eventGateway.onGetDetail = (_) async => _success(_detail(_timedEvent()));
      eventGateway.onList = (_) async => _success(
        EventOccurrenceListResponseDto(
          items: [_timedOccurrence(key: 'occ-1')],
          hasMore: false,
          nextCursor: null,
        ),
      );
      eventGateway.onOccurrence = (_, _) async =>
          _failure('OCCURRENCE_OPERATION_INVALID', 'invalid operation');
      final reconcile = _FakeReconcileUseCase();
      final controller = _controller(
        eventGateway: eventGateway,
        timezoneGateway: _FakeTimezoneGateway(),
        reconcile: reconcile,
        now: now,
      );
      await controller.load();

      final result = await controller.skipOccurrence('occ-1');

      expect(result.succeeded, isFalse);
      expect(result.failure!.code, 'OCCURRENCE_OPERATION_INVALID');
      expect(controller.state.occurrences.single.status, 'scheduled');
      expect(
        controller.state.actionFailure!.code,
        'OCCURRENCE_OPERATION_INVALID',
      );
      expect(reconcile.requests, isEmpty);
    },
  );

  for (final mutation in [
    RecurringEventSeriesMutation.complete,
    RecurringEventSeriesMutation.reopen,
    RecurringEventSeriesMutation.cancel,
  ]) {
    test(
      '${mutation.name} series refreshes authoritative projection',
      () async {
        final initialStatus = mutation == RecurringEventSeriesMutation.reopen
            ? 'completed'
            : 'active';
        final expectedStatus = switch (mutation) {
          RecurringEventSeriesMutation.complete => 'completed',
          RecurringEventSeriesMutation.reopen => 'active',
          RecurringEventSeriesMutation.cancel => 'cancelled',
          RecurringEventSeriesMutation.delete => throw StateError('unused'),
        };
        var current = _timedEvent(status: initialStatus);
        final eventGateway = _FakeEventGateway();
        eventGateway.onGetDetail = (_) async => _success(_detail(current));
        eventGateway.onList = (_) async => _success(
          const EventOccurrenceListResponseDto(
            items: [],
            hasMore: false,
            nextCursor: null,
          ),
        );
        eventGateway.onSeries = (operation, _) async {
          expect(operation, mutation);
          current = _timedEvent(status: expectedStatus);
          return _success(current);
        };
        final reconcile = _FakeReconcileUseCase();
        final controller = _controller(
          eventGateway: eventGateway,
          timezoneGateway: _FakeTimezoneGateway(),
          reconcile: reconcile,
          now: now,
        );
        await controller.load();

        final result = await switch (mutation) {
          RecurringEventSeriesMutation.complete => controller.completeSeries(),
          RecurringEventSeriesMutation.reopen => controller.reopenSeries(),
          RecurringEventSeriesMutation.cancel => controller.cancelSeries(),
          RecurringEventSeriesMutation.delete => throw StateError('unused'),
        };

        expect(result.succeeded, isTrue);
        expect(controller.state.event!.status, expectedStatus);
        expect(eventGateway.seriesCalls.single.$2.recurrenceRevision, 7);
        expect(eventGateway.detailRequests, hasLength(2));
        expect(reconcile.requests, hasLength(1));
        expect(controller.state.seriesMutation, isNull);
      },
    );
  }

  test('series failure leaves event projection unchanged', () async {
    final eventGateway = _FakeEventGateway();
    eventGateway.onGetDetail = (_) async => _success(_detail(_timedEvent()));
    eventGateway.onList = (_) async => _success(
      const EventOccurrenceListResponseDto(
        items: [],
        hasMore: false,
        nextCursor: null,
      ),
    );
    eventGateway.onSeries = (_, _) async =>
        _failure('RECURRENCE_REVISION_CONFLICT', 'stale revision');
    final reconcile = _FakeReconcileUseCase();
    final controller = _controller(
      eventGateway: eventGateway,
      timezoneGateway: _FakeTimezoneGateway(),
      reconcile: reconcile,
      now: now,
    );
    await controller.load();

    final result = await controller.completeSeries();

    expect(result.failure!.code, 'RECURRENCE_REVISION_CONFLICT');
    expect(controller.state.event!.status, 'active');
    expect(eventGateway.detailRequests, hasLength(1));
    expect(reconcile.requests, isEmpty);
  });

  test('delete series is always soft/all_occurrences and reconciles', () async {
    final event = _timedEvent();
    final eventGateway = _FakeEventGateway();
    eventGateway.onGetDetail = (_) async => _success(_detail(event));
    eventGateway.onList = (_) async => _success(
      EventOccurrenceListResponseDto(
        items: [_timedOccurrence(key: 'occ-1')],
        hasMore: false,
        nextCursor: null,
      ),
    );
    eventGateway.onDelete = (_) async => _success(
      _timedEvent(deletedAt: DateTime.parse('2026-08-05T12:30:00Z')),
    );
    final reconcile = _FakeReconcileUseCase();
    final controller = _controller(
      eventGateway: eventGateway,
      timezoneGateway: _FakeTimezoneGateway(),
      reconcile: reconcile,
      now: now,
    );
    await controller.load();

    final result = await controller.deleteSeries(reason: 'user_deleted');

    expect(result.succeeded, isTrue);
    expect(eventGateway.deleteRequests.single.toJson(), {
      'id': 'event-1',
      'delete_mode': 'soft',
      'recurrence_delete_scope': 'all_occurrences',
      'expected_recurrence_revision': 7,
      'reason': 'user_deleted',
    });
    expect(controller.state.isDeleted, isTrue);
    expect(controller.state.occurrences, isEmpty);
    expect(reconcile.requests, hasLength(1));
  });

  test(
    'delete series rejects a mismatched Native recurrence identity',
    () async {
      final eventGateway = _FakeEventGateway();
      eventGateway.onGetDetail = (_) async => _success(_detail(_timedEvent()));
      eventGateway.onList = (_) async => _success(
        const EventOccurrenceListResponseDto(
          items: [],
          hasMore: false,
          nextCursor: null,
        ),
      );
      eventGateway.onDelete = (_) async => _success(
        _timedEvent(
          recurrenceId: 'another-recurrence',
          deletedAt: DateTime.parse('2026-08-05T12:30:00Z'),
        ),
      );
      final reconcile = _FakeReconcileUseCase();
      final controller = _controller(
        eventGateway: eventGateway,
        timezoneGateway: _FakeTimezoneGateway(),
        reconcile: reconcile,
        now: now,
      );
      await controller.load();

      final result = await controller.deleteSeries();

      expect(result.succeeded, isFalse);
      expect(controller.state.isDeleted, isFalse);
      expect(reconcile.requests, isEmpty);
    },
  );

  test(
    'committed mutation remains successful when reconcile fails and exposes warning',
    () async {
      final eventGateway = _FakeEventGateway();
      eventGateway.onGetDetail = (_) async => _success(_detail(_timedEvent()));
      eventGateway.onList = (_) async => _success(
        EventOccurrenceListResponseDto(
          items: [_timedOccurrence(key: 'occ-1')],
          hasMore: false,
          nextCursor: null,
        ),
      );
      eventGateway.onOccurrence = (_, _) async =>
          _success(_occurrenceState(status: 'completed'));
      final reconcile = _FakeReconcileUseCase(
        response: _failure('ALARM_SCHEDULE_FAILED', 'alarm unavailable'),
      );
      final controller = _controller(
        eventGateway: eventGateway,
        timezoneGateway: _FakeTimezoneGateway(),
        reconcile: reconcile,
        now: now,
      );
      await controller.load();

      final result = await controller.completeOccurrence('occ-1');

      expect(result.succeeded, isTrue);
      expect(result.warning!.code, 'ALARM_SCHEDULE_FAILED');
      expect(controller.state.occurrences.single.status, 'completed');
      expect(controller.state.reconcileWarning!.code, 'ALARM_SCHEDULE_FAILED');
    },
  );

  test('non-recurring Event rejects recurrence-only actions', () async {
    final eventGateway = _FakeEventGateway()
      ..onGetDetail = (_) async =>
          _success(_detail(_timedEvent(recurring: false)));
    final reconcile = _FakeReconcileUseCase();
    final controller = _controller(
      eventGateway: eventGateway,
      timezoneGateway: _FakeTimezoneGateway(),
      reconcile: reconcile,
      now: now,
    );
    await controller.load();

    final result = await controller.completeSeries();

    expect(result.succeeded, isFalse);
    expect(result.failure!.message, contains('不是重复日程'));
    expect(eventGateway.seriesCalls, isEmpty);
    expect(reconcile.requests, isEmpty);
  });
}

RecurringEventDetailController _controller({
  required _FakeEventGateway eventGateway,
  required _FakeTimezoneGateway timezoneGateway,
  required DateTime now,
  _FakeReconcileUseCase? reconcile,
  String? focusOccurrenceKey,
}) {
  return RecurringEventDetailController(
    eventId: 'event-1',
    gateway: eventGateway,
    timezoneService: TimezoneApplicationService(timezoneGateway),
    reconcileReminderScheduleUseCase: reconcile ?? _FakeReconcileUseCase(),
    clock: () => now,
    focusOccurrenceKey: focusOccurrenceKey,
  );
}

EventDetailResponseDto _detail(EventResponseDto event) {
  return EventDetailResponseDto(
    event: event,
    recurrence: event.hasRecurrence ? _recurrence(event) : null,
    reminders: const [],
    category: null,
  );
}

EventResponseDto _timedEvent({
  bool recurring = true,
  String title = 'Daily review',
  String status = 'active',
  String recurrenceId = 'recurrence-1',
  int recurrenceRevision = 7,
  DateTime? deletedAt,
}) {
  return EventResponseDto(
    id: 'event-1',
    title: title,
    startAt: DateTime.parse('2026-08-05T09:00:00Z'),
    endAt: DateTime.parse('2026-08-05T10:00:00Z'),
    startDate: null,
    endDate: null,
    isAllDay: false,
    hasRecurrence: recurring,
    status: status,
    recurrenceId: recurring ? recurrenceId : null,
    recurrenceRevision: recurring ? recurrenceRevision : null,
    timezone: 'Europe/London',
    source: 'manual',
    createdAt: DateTime.parse('2026-08-01T00:00:00Z'),
    updatedAt: DateTime.parse('2026-08-05T12:00:00Z'),
    deletedAt: deletedAt,
  );
}

EventResponseDto _allDayEvent() {
  return EventResponseDto(
    id: 'event-1',
    title: 'All day plan',
    startAt: null,
    endAt: null,
    startDate: '2026-08-06',
    endDate: '2026-08-07',
    isAllDay: true,
    hasRecurrence: true,
    status: 'active',
    recurrenceId: 'recurrence-1',
    recurrenceRevision: 7,
    timezone: 'Pacific/Kiritimati',
    source: 'manual',
    createdAt: DateTime.parse('2026-08-01T00:00:00Z'),
    updatedAt: DateTime.parse('2026-08-05T12:00:00Z'),
  );
}

RecurrenceResponseDto _recurrence(EventResponseDto event) {
  return RecurrenceResponseDto(
    recurrenceId: 'recurrence-1',
    revision: 7,
    frequency: 'daily',
    interval: 1,
    startAt: event.startAt,
    startDate: event.startDate,
    timezone: event.timezone,
    dayOfMonth: null,
    daysOfWeek: const [],
    createdAt: DateTime.parse('2026-08-01T00:00:00Z'),
  );
}

EventOccurrenceResponseDto _timedOccurrence({
  required String key,
  String start = '2026-08-05T09:00:00Z',
  EventOccurrenceStateResponseDto? state,
}) {
  final startAt = DateTime.parse(start);
  return EventOccurrenceResponseDto(
    eventId: 'event-1',
    recurrenceRevision: 7,
    occurrenceKey: key,
    occurrenceStartAt: startAt,
    occurrenceEndAt: startAt.add(const Duration(hours: 1)),
    occurrenceStartDate: null,
    occurrenceEndDate: null,
    timezone: 'Europe/London',
    state: state,
  );
}

EventOccurrenceResponseDto _allDayOccurrence() {
  return const EventOccurrenceResponseDto(
    eventId: 'event-1',
    recurrenceRevision: 7,
    occurrenceKey: 'all-day-occ-1',
    occurrenceStartAt: null,
    occurrenceEndAt: null,
    occurrenceStartDate: '2026-08-06',
    occurrenceEndDate: '2026-08-07',
    timezone: 'Pacific/Kiritimati',
    state: null,
  );
}

EventOccurrenceStateResponseDto _occurrenceState({required String status}) {
  final timestamp = DateTime.parse('2026-08-05T12:30:00Z');
  return EventOccurrenceStateResponseDto(
    eventId: 'event-1',
    recurrenceRevision: 7,
    occurrenceKey: 'occ-1',
    occurrenceStartAt: DateTime.parse('2026-08-05T09:00:00Z'),
    occurrenceStartDate: null,
    status: status,
    stateChangedAt: timestamp,
    reopenedAt: status == 'scheduled' ? timestamp : null,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

LocalWallDateTime _wallFromInstant(DateTime instant, {int hours = 0}) {
  return LocalWallDateTime.fromDateTimeComponents(
    instant.toUtc().add(Duration(hours: hours)),
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
      requestId: 'request-1',
    ),
    isNativeResult: true,
  );
}

NativeInvocation<T> _failure<T>(String code, String message) {
  return NativeInvocation<T>(
    rawResponse: const {},
    result: NativeResultDto<T>(
      ok: false,
      data: null,
      error: NativeErrorDto(code: code, message: message),
      contractVersion: 2,
      requestId: 'request-1',
    ),
    isNativeResult: true,
  );
}

class _FakeEventGateway implements EventNativeGateway {
  Future<NativeInvocation<EventDetailResponseDto>> Function(
    GetEventDetailRequestDto request,
  )?
  onGetDetail;
  Future<NativeInvocation<EventOccurrenceListResponseDto>> Function(
    ListEventOccurrencesRequestDto request,
  )?
  onList;
  Future<NativeInvocation<EventOccurrenceStateResponseDto>> Function(
    RecurringEventOccurrenceMutation mutation,
    EventOccurrenceOperationRequestDto request,
  )?
  onOccurrence;
  Future<NativeInvocation<EventResponseDto>> Function(
    RecurringEventSeriesMutation mutation,
    EventSeriesOperationRequestDto request,
  )?
  onSeries;
  Future<NativeInvocation<EventResponseDto>> Function(
    DeleteEventRequestDto request,
  )?
  onDelete;

  final List<GetEventDetailRequestDto> detailRequests = [];
  final List<ListEventOccurrencesRequestDto> listRequests = [];
  final List<
    (RecurringEventOccurrenceMutation, EventOccurrenceOperationRequestDto)
  >
  occurrenceCalls = [];
  final List<(RecurringEventSeriesMutation, EventSeriesOperationRequestDto)>
  seriesCalls = [];
  final List<DeleteEventRequestDto> deleteRequests = [];

  @override
  Future<NativeInvocation<EventDetailResponseDto>> getEventDetail(
    GetEventDetailRequestDto request,
  ) {
    detailRequests.add(request);
    return onGetDetail!(request);
  }

  @override
  Future<NativeInvocation<EventOccurrenceListResponseDto>> listOccurrences(
    ListEventOccurrencesRequestDto request,
  ) {
    listRequests.add(request);
    return onList!(request);
  }

  Future<NativeInvocation<EventOccurrenceStateResponseDto>> _mutateOccurrence(
    RecurringEventOccurrenceMutation mutation,
    EventOccurrenceOperationRequestDto request,
  ) {
    occurrenceCalls.add((mutation, request));
    return onOccurrence!(mutation, request);
  }

  @override
  Future<NativeInvocation<EventOccurrenceStateResponseDto>> completeOccurrence(
    EventOccurrenceOperationRequestDto request,
  ) {
    return _mutateOccurrence(
      RecurringEventOccurrenceMutation.complete,
      request,
    );
  }

  @override
  Future<NativeInvocation<EventOccurrenceStateResponseDto>> reopenOccurrence(
    EventOccurrenceOperationRequestDto request,
  ) {
    return _mutateOccurrence(RecurringEventOccurrenceMutation.reopen, request);
  }

  @override
  Future<NativeInvocation<EventOccurrenceStateResponseDto>> skipOccurrence(
    EventOccurrenceOperationRequestDto request,
  ) {
    return _mutateOccurrence(RecurringEventOccurrenceMutation.skip, request);
  }

  @override
  Future<NativeInvocation<EventOccurrenceStateResponseDto>> cancelOccurrence(
    EventOccurrenceOperationRequestDto request,
  ) {
    return _mutateOccurrence(RecurringEventOccurrenceMutation.cancel, request);
  }

  Future<NativeInvocation<EventResponseDto>> _mutateSeries(
    RecurringEventSeriesMutation mutation,
    EventSeriesOperationRequestDto request,
  ) {
    seriesCalls.add((mutation, request));
    return onSeries!(mutation, request);
  }

  @override
  Future<NativeInvocation<EventResponseDto>> completeSeries(
    EventSeriesOperationRequestDto request,
  ) {
    return _mutateSeries(RecurringEventSeriesMutation.complete, request);
  }

  @override
  Future<NativeInvocation<EventResponseDto>> reopenSeries(
    EventSeriesOperationRequestDto request,
  ) {
    return _mutateSeries(RecurringEventSeriesMutation.reopen, request);
  }

  @override
  Future<NativeInvocation<EventResponseDto>> cancelSeries(
    EventSeriesOperationRequestDto request,
  ) {
    return _mutateSeries(RecurringEventSeriesMutation.cancel, request);
  }

  @override
  Future<NativeInvocation<EventResponseDto>> deleteEvent(
    DeleteEventRequestDto request,
  ) {
    deleteRequests.add(request);
    return onDelete!(request);
  }

  @override
  Future<NativeInvocation<EventResponseDto>> completeEvent(
    CompleteEventRequestDto request,
  ) => throw UnimplementedError();

  @override
  Future<NativeInvocation<EventResponseDto>> createEvent(
    CreateEventRequestDto request,
  ) => throw UnimplementedError();

  @override
  Future<NativeInvocation<EventListResponseDto>> readEvents(
    SearchEventRequestDto request,
  ) => throw UnimplementedError();

  @override
  Future<NativeInvocation<EventResponseDto>> reopenEvent(
    ReopenEventRequestDto request,
  ) => throw UnimplementedError();

  @override
  Future<NativeInvocation<EventResponseDto>> updateEvent(
    UpdateEventRequestDto request,
  ) => throw UnimplementedError();
}

class _FakeTimezoneGateway implements TimezoneNativeGateway {
  _FakeTimezoneGateway({
    LocalWallDateTime Function(String timezone, DateTime instant)? localize,
  }) : _localize = localize ?? ((_, instant) => _wallFromInstant(instant));

  final LocalWallDateTime Function(String timezone, DateTime instant) _localize;
  final List<LocalizeInstantsRequestDto> localizeRequests = [];

  @override
  Future<NativeInvocation<LocalizeInstantsResponseDto>> localizeInstants(
    LocalizeInstantsRequestDto request,
  ) async {
    localizeRequests.add(request);
    return _success(
      LocalizeInstantsResponseDto(
        timezone: request.timezone,
        items: request.instants
            .map(
              (instant) => LocalizedInstantDto(
                instant: instant,
                localDateTime: _localize(request.timezone, instant),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  @override
  Future<NativeInvocation<DeviceTimezoneResponseDto>> getDeviceTimezone() =>
      throw UnimplementedError();

  @override
  Future<NativeInvocation<ResolveLocalDateTimeResponseDto>>
  resolveLocalDateTime(ResolveLocalDateTimeRequestDto request) =>
      throw UnimplementedError();
}

class _FakeReconcileUseCase implements ReconcileReminderScheduleUseCase {
  _FakeReconcileUseCase({
    NativeInvocation<ReconcileReminderScheduleResponseDto>? response,
  }) : response =
           response ??
           _success(
             const ReconcileReminderScheduleResponseDto(
               action: 'unchanged',
               nextRemindAt: null,
               processedDueCount: 0,
               failedCount: 0,
               continuationEnqueued: false,
               failedReminderIds: [],
             ),
           );

  final NativeInvocation<ReconcileReminderScheduleResponseDto> response;
  final List<ReconcileReminderScheduleRequestDto> requests = [];

  @override
  bool get isReconciling => false;

  @override
  Future<NativeInvocation<ReconcileReminderScheduleResponseDto>> execute({
    required ReminderScheduleTrigger triggerSource,
    bool force = false,
  }) async {
    requests.add(
      ReconcileReminderScheduleRequestDto(
        triggerSource: triggerSource,
        force: force,
      ),
    );
    return response;
  }
}
