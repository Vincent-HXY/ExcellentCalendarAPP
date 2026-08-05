import 'dart:async';

import 'package:excellent_calendar/application/event/create_event_use_case.dart';
import 'package:excellent_calendar/application/event/complete_event_use_case.dart';
import 'package:excellent_calendar/application/event/reopen_event_use_case.dart';
import 'package:excellent_calendar/application/event/update_event_use_case.dart';
import 'package:excellent_calendar/application/reminder/reconcile_reminder_schedule_use_case.dart';
import 'package:excellent_calendar/gateway_interfaces/event_native_gateway.dart';
import 'package:excellent_calendar/native_contract/event/complete_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/create_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_list_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/reopen_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/search_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/update_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/reconcile_reminder_schedule_dto.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_reminder_gateway.dart';
import 'fixtures/notification_fixtures.dart';
import 'fixtures/reminder_fixtures.dart';

void main() {
  test('timed Event DTOs reject unresolved local DateTime values', () {
    final localStart = DateTime(2026, 7, 5, 10);
    final localEnd = DateTime(2026, 7, 5, 11);

    expect(
      () => CreateEventRequestDto.timed(
        title: 'Meeting',
        startAt: localStart,
        endAt: localEnd,
        timezone: 'Europe/London',
        source: 'manual',
      ).toJson(),
      throwsFormatException,
    );
    expect(
      () => UpdateEventRequestDto(
        id: 'event-1',
        startAt: localStart,
        endAt: localEnd,
        isAllDay: false,
        timezone: 'Europe/London',
      ).toJson(),
      throwsFormatException,
    );
  });

  test(
    'successful event mutation reconciles the durable reminder queue',
    () async {
      final reminderGateway = _reminderGateway();
      final reconciler = ReconcileReminderScheduleUseCase(reminderGateway);
      final create = CreateEventUseCase(
        _EventGateway(),
        reconcileReminderScheduleUseCase: reconciler,
      );
      final update = UpdateEventUseCase(
        _EventGateway(),
        reconcileReminderScheduleUseCase: reconciler,
      );

      await create.execute(_createRequest());
      await update.execute(
        const UpdateEventRequestDto(id: 'event-1', title: 'Updated'),
      );

      expect(reminderGateway.reconcileScheduleCallCount, 2);
      expect(
        reminderGateway.lastReconcileScheduleRequest!.triggerSource,
        ReminderScheduleTrigger.mutation,
      );
      expect(reminderGateway.lastReconcileScheduleRequest!.force, isTrue);
    },
  );

  test(
    'successful event lifecycle mutations reconcile the reminder queue',
    () async {
      final reminderGateway = _reminderGateway();
      final reconciler = ReconcileReminderScheduleUseCase(reminderGateway);
      final complete = CompleteEventUseCase(
        _EventGateway(),
        reconcileReminderScheduleUseCase: reconciler,
      );
      final reopen = ReopenEventUseCase(
        _EventGateway(),
        reconcileReminderScheduleUseCase: reconciler,
      );

      await complete.execute(
        const CompleteEventRequestDto(eventId: 'event-1', source: 'manual'),
      );
      await reopen.execute(const ReopenEventRequestDto(eventId: 'event-1'));

      expect(reminderGateway.reconcileScheduleCallCount, 2);
      expect(
        reminderGateway.lastReconcileScheduleRequest!.triggerSource,
        ReminderScheduleTrigger.mutation,
      );
      expect(reminderGateway.lastReconcileScheduleRequest!.force, isTrue);
    },
  );

  test('failed event creation does not reconcile reminders', () async {
    final reminderGateway = _reminderGateway();
    final useCase = CreateEventUseCase(
      _EventGateway(createFails: true),
      reconcileReminderScheduleUseCase: ReconcileReminderScheduleUseCase(
        reminderGateway,
      ),
    );

    await useCase.execute(_createRequest());

    expect(reminderGateway.reconcileScheduleCallCount, 0);
  });

  test('concurrent reconcile requests share one native invocation', () async {
    final pending =
        Completer<NativeInvocation<ReconcileReminderScheduleResponseDto>>();
    final gateway = _reminderGateway(onReconcile: (_) => pending.future);
    final useCase = ReconcileReminderScheduleUseCase(gateway);

    final first = useCase.execute(
      triggerSource: ReminderScheduleTrigger.appStart,
    );
    final second = useCase.execute(
      triggerSource: ReminderScheduleTrigger.appResume,
    );
    expect(gateway.reconcileScheduleCallCount, 1);
    pending.complete(successInvocation(reconcileResponse));
    await Future.wait([first, second]);
    expect(useCase.isReconciling, isFalse);
  });

  test(
    'event use case exposes reconcile failure instead of discarding it',
    () async {
      final gateway = _reminderGateway(
        onReconcile: (_) async =>
            failureInvocation(code: 'ALARM_SCHEDULE_FAILED'),
      );
      final useCase = CreateEventUseCase(
        _EventGateway(),
        reconcileReminderScheduleUseCase: ReconcileReminderScheduleUseCase(
          gateway,
        ),
      );

      final eventResult = await useCase.execute(_createRequest());

      expect(eventResult.result.ok, isTrue);
      expect(useCase.lastReconcileInvocation?.result.ok, isFalse);
    },
  );
}

FakeReminderGateway _reminderGateway({
  ReconcileReminderScheduleHandler? onReconcile,
}) => FakeReminderGateway(
  onCreate: (_) async => reminderSuccessInvocation(),
  onCancel: (_) async => reminderSuccessInvocation(),
  onReconcileSchedule:
      onReconcile ?? (_) async => successInvocation(reconcileResponse),
);

CreateEventRequestDto _createRequest() => CreateEventRequestDto(
  title: 'Meeting',
  startAt: DateTime.utc(2026, 7, 5, 10),
  endAt: DateTime.utc(2026, 7, 5, 11),
  isAllDay: false,
  timezone: 'Asia/Shanghai',
  source: 'manual',
);

class _EventGateway implements EventNativeGateway {
  _EventGateway({this.createFails = false});
  final bool createFails;

  @override
  Future<NativeInvocation<EventResponseDto>> createEvent(
    CreateEventRequestDto request,
  ) async {
    if (createFails) return failureInvocation(code: 'EVENT_VALIDATION_FAILED');
    return successInvocation(_event(title: request.title));
  }

  @override
  Future<NativeInvocation<EventResponseDto>> updateEvent(
    UpdateEventRequestDto request,
  ) async => successInvocation(_event(title: request.title ?? 'Meeting'));

  EventResponseDto _event({
    required String title,
    String status = 'active',
    DateTime? completedAt,
  }) => EventResponseDto(
    id: 'event-1',
    title: title,
    startAt: DateTime.utc(2026, 7, 5, 10),
    endAt: DateTime.utc(2026, 7, 5, 11),
    startDate: null,
    endDate: null,
    isAllDay: false,
    hasRecurrence: false,
    status: status,
    completedAt: completedAt,
    recurrenceId: null,
    recurrenceRevision: null,
    timezone: 'Asia/Shanghai',
    source: 'manual',
    createdAt: DateTime.utc(2026, 7, 5),
    updatedAt: DateTime.utc(2026, 7, 5),
  );

  @override
  Future<NativeInvocation<EventResponseDto>> completeEvent(
    CompleteEventRequestDto request,
  ) async => successInvocation(
    _event(
      title: 'Meeting',
      status: 'completed',
      completedAt: DateTime.utc(2026, 7, 5, 12),
    ),
  );
  @override
  Future<NativeInvocation<EventListResponseDto>> readEvents(
    SearchEventRequestDto request,
  ) => throw UnimplementedError();
  @override
  Future<NativeInvocation<EventResponseDto>> reopenEvent(
    ReopenEventRequestDto request,
  ) async => successInvocation(_event(title: 'Meeting'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
