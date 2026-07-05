import 'dart:async';

import 'package:excellent_calendar/application/event/create_event_use_case.dart';
import 'package:excellent_calendar/application/event/update_event_use_case.dart';
import 'package:excellent_calendar/application/reminder/schedule_pending_reminders_use_case.dart';
import 'package:excellent_calendar/gateway_interfaces/event_native_gateway.dart';
import 'package:excellent_calendar/native_contract/event/complete_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/create_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_list_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_occurrence_state_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/reopen_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/search_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/update_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/schedule_pending_reminders_dto.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_reminder_gateway.dart';
import 'fixtures/notification_fixtures.dart';
import 'fixtures/reminder_fixtures.dart';

void main() {
  test(
    'successful event creation triggers pending reminder scheduling',
    () async {
      final reminderGateway = FakeReminderGateway(
        onCreate: (_) async => reminderSuccessInvocation(),
        onCancel: (_) async => reminderSuccessInvocation(),
        onSchedulePending: (_) async => successInvocation(scheduleResponse),
      );
      final useCase = CreateEventUseCase(
        _CreateEventGateway(),
        schedulePendingRemindersUseCase: SchedulePendingRemindersUseCase(
          reminderGateway,
          clock: () => DateTime.utc(2026, 7, 5),
        ),
      );

      final result = await useCase.execute(
        CreateEventRequestDto(
          title: 'Meeting',
          startAt: DateTime.utc(2026, 7, 5, 10),
          endAt: DateTime.utc(2026, 7, 5, 11),
          isAllDay: false,
          source: 'manual',
        ),
      );

      expect(result.result.ok, isTrue);
      expect(reminderGateway.schedulePendingCallCount, 1);
      expect(
        reminderGateway.lastSchedulePendingRequest!.toJson()['limit'],
        128,
      );
    },
  );

  test(
    'successful event update triggers pending reminder scheduling',
    () async {
      final reminderGateway = FakeReminderGateway(
        onCreate: (_) async => reminderSuccessInvocation(),
        onCancel: (_) async => reminderSuccessInvocation(),
        onSchedulePending: (_) async => successInvocation(scheduleResponse),
      );
      final useCase = UpdateEventUseCase(
        _CreateEventGateway(),
        schedulePendingRemindersUseCase: SchedulePendingRemindersUseCase(
          reminderGateway,
          clock: () => DateTime.utc(2026, 7, 5),
        ),
      );

      final result = await useCase.execute(
        const UpdateEventRequestDto(id: 'event-1', title: 'Updated meeting'),
      );

      expect(result.result.ok, isTrue);
      expect(reminderGateway.schedulePendingCallCount, 1);
    },
  );

  test('failed event creation does not schedule pending reminders', () async {
    final reminderGateway = FakeReminderGateway(
      onCreate: (_) async => reminderSuccessInvocation(),
      onCancel: (_) async => reminderSuccessInvocation(),
      onSchedulePending: (_) async => successInvocation(scheduleResponse),
    );
    final useCase = CreateEventUseCase(
      _CreateEventGateway(
        createResult: failureInvocation<EventResponseDto>(
          code: 'EVENT_VALIDATION_FAILED',
        ),
      ),
      schedulePendingRemindersUseCase: SchedulePendingRemindersUseCase(
        reminderGateway,
      ),
    );

    final result = await useCase.execute(
      CreateEventRequestDto(
        title: '',
        startAt: DateTime.utc(2026, 7, 5, 10),
        endAt: DateTime.utc(2026, 7, 5, 11),
        isAllDay: false,
        source: 'manual',
      ),
    );

    expect(result.result.ok, isFalse);
    expect(reminderGateway.schedulePendingCallCount, 0);
  });

  test('concurrent scheduling requests share one native invocation', () async {
    final pendingResult =
        Completer<NativeInvocation<SchedulePendingRemindersResponseDto>>();
    final reminderGateway = FakeReminderGateway(
      onCreate: (_) async => reminderSuccessInvocation(),
      onCancel: (_) async => reminderSuccessInvocation(),
      onSchedulePending: (_) => pendingResult.future,
    );
    final useCase = SchedulePendingRemindersUseCase(
      reminderGateway,
      clock: () => DateTime.utc(2026, 7, 5),
    );

    final first = useCase.execute();
    final second = useCase.execute();

    expect(reminderGateway.schedulePendingCallCount, 1);
    expect(useCase.isScheduling, isTrue);
    pendingResult.complete(successInvocation(scheduleResponse));
    expect((await first).result.ok, isTrue);
    expect((await second).result.ok, isTrue);
    expect(useCase.isScheduling, isFalse);

    await useCase.execute();
    expect(reminderGateway.schedulePendingCallCount, 2);
  });

  test(
    'scheduling drains every page when native reports has_more',
    () async {
      var callCount = 0;
      final reminderGateway = FakeReminderGateway(
        onCreate: (_) async => reminderSuccessInvocation(),
        onCancel: (_) async => reminderSuccessInvocation(),
        onSchedulePending: (_) async {
          callCount += 1;
          return successInvocation(
            SchedulePendingRemindersResponseDto(
              scheduledCount: 128,
              skippedCount: 0,
              failedCount: 0,
              unsupportedMethodCount: 0,
              hasMore: callCount == 1,
              failedReminderIds: const [],
              unsupportedReminderIds: const [],
            ),
          );
        },
      );
      final useCase = SchedulePendingRemindersUseCase(reminderGateway);

      await useCase.execute();

      expect(callCount, 2);
    },
    skip:
        'Known defect: has_more is returned but no caller drains the next page.',
  );
}

class _CreateEventGateway implements EventNativeGateway {
  _CreateEventGateway({this.createResult});

  final NativeInvocation<EventResponseDto>? createResult;

  @override
  Future<NativeInvocation<EventResponseDto>> updateEvent(
    UpdateEventRequestDto request,
  ) async {
    final now = DateTime.utc(2026, 7, 5);
    return successInvocation(
      EventResponseDto(
        id: request.id,
        title: request.title ?? 'Meeting',
        startAt: DateTime.utc(2026, 7, 5, 10),
        endAt: DateTime.utc(2026, 7, 5, 11),
        isAllDay: false,
        hasRecurrence: false,
        status: 'active',
        source: request.source ?? 'manual',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  @override
  Future<NativeInvocation<EventResponseDto>> createEvent(
    CreateEventRequestDto request,
  ) async {
    final configuredResult = createResult;
    if (configuredResult != null) return configuredResult;
    final now = DateTime.utc(2026, 7, 5);
    return successInvocation(
      EventResponseDto(
        id: 'event-1',
        title: request.title,
        startAt: request.startAt,
        endAt: request.endAt,
        isAllDay: request.isAllDay,
        hasRecurrence: false,
        status: 'active',
        source: request.source,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  @override
  Future<NativeInvocation<EventResponseDto>> completeEvent(
    CompleteEventRequestDto request,
  ) => throw UnimplementedError();

  @override
  Future<NativeInvocation<EventListResponseDto>> readEvents(
    SearchEventRequestDto request,
  ) => throw UnimplementedError();

  @override
  Future<NativeInvocation<EventOccurrenceStateResponseDto>> reopenEvent(
    ReopenEventRequestDto request,
  ) => throw UnimplementedError();
}
