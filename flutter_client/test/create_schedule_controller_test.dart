import 'package:excellent_calendar/application/event/create_event_use_case.dart';
import 'package:excellent_calendar/application/event/create_schedule_controller.dart';
import 'package:excellent_calendar/application/timezone/timezone_application_service.dart';
import 'package:excellent_calendar/gateway_interfaces/event_native_gateway.dart';
import 'package:excellent_calendar/native_contract/event/create_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_response_dto.dart';
import 'package:excellent_calendar/native_contract/runtime/local_wall_date_time.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';
import 'package:excellent_calendar/native_contract/ring/ring_contract_enums.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_timezone_gateway.dart';
import 'fakes/fake_ring_gateway.dart';
import 'fixtures/notification_fixtures.dart';
import 'fixtures/ring_fixtures.dart';

void main() {
  test('submit owns timezone, recurrence, reminder, and DTO mapping', () async {
    final eventGateway = _RecordingEventGateway();
    final timezoneGateway = FakeTimezoneGateway(
      deviceTimezones: const ['Asia/Shanghai'],
    );
    final controller = CreateScheduleController(
      createEventUseCase: CreateEventUseCase(eventGateway),
      timezoneService: TimezoneApplicationService(timezoneGateway),
    );

    final result = await controller.submit(
      const CreateScheduleDraft(
        title: '  设计复盘  ',
        note: '  记录结论  ',
        location: '  会议室  ',
        start: LocalWallDateTime(
          year: 2026,
          month: 8,
          day: 10,
          hour: 9,
          minute: 0,
          second: 0,
        ),
        end: LocalWallDateTime(
          year: 2026,
          month: 8,
          day: 10,
          hour: 10,
          minute: 0,
          second: 0,
        ),
        isAllDay: false,
        recurrence: CreateScheduleRecurrence.daily,
        reminderAdvanceMinutes: [45],
        isRingingReminderEnabled: false,
        categoryId: 'cat_work',
        previousTimezone: 'UTC',
      ),
    );

    expect(result.succeeded, isTrue);
    expect(result.timezone, 'Asia/Shanghai');
    expect(result.timezoneChanged, isTrue);
    final request = eventGateway.createRequests.single;
    expect(request.title, '设计复盘');
    expect(request.content, '记录结论');
    expect(request.location, '会议室');
    expect(request.timezone, 'Asia/Shanghai');
    expect(request.recurrence?.frequency, 'daily');
    expect(
      request.reminders.single.toEventJson(recurring: true),
      containsPair('advance_minutes', 45),
    );
    expect(
      request.reminders.single.toEventJson(recurring: true),
      containsPair('methods', ['popup']),
    );
    expect(request.categoryId, 'cat_work');
    expect(request.importance, 'unimportant_noturgent');
    expect(request.source, 'manual');
  });

  test('business validation fails before timezone or Native work', () async {
    final eventGateway = _RecordingEventGateway();
    final timezoneGateway = FakeTimezoneGateway();
    final controller = CreateScheduleController(
      createEventUseCase: CreateEventUseCase(eventGateway),
      timezoneService: TimezoneApplicationService(timezoneGateway),
    );

    final result = await controller.submit(
      const CreateScheduleDraft(
        title: '全天复盘',
        note: '',
        location: '',
        start: LocalWallDateTime(
          year: 2026,
          month: 8,
          day: 10,
          hour: 0,
          minute: 0,
          second: 0,
        ),
        end: LocalWallDateTime(
          year: 2026,
          month: 8,
          day: 11,
          hour: 0,
          minute: 0,
          second: 0,
        ),
        isAllDay: true,
        recurrence: CreateScheduleRecurrence.daily,
        reminderAdvanceMinutes: [15],
        isRingingReminderEnabled: false,
      ),
    );

    expect(result.outcome, CreateScheduleSubmitOutcome.validationFailure);
    expect(result.message, '全天重复日程暂不支持提醒');
    expect(eventGateway.createRequests, isEmpty);
    expect(timezoneGateway.resolveRequests, isEmpty);
  });

  test(
    'ring save rechecks capability and submits ring without popup',
    () async {
      final eventGateway = _RecordingEventGateway();
      final ringCalls = <String>[];
      final ringGateway = FakeRingGateway(
        callLog: ringCalls,
        onGetState: () async => successInvocation(ringSnapshot()),
      );
      final controller = CreateScheduleController(
        createEventUseCase: CreateEventUseCase(eventGateway),
        timezoneService: TimezoneApplicationService(FakeTimezoneGateway()),
        ringGateway: ringGateway,
      );

      final toggleCheck = await controller.checkRingCapability();
      final result = await controller.submit(_ringDraft());

      expect(toggleCheck.canEnable, isTrue);
      expect(result.succeeded, isTrue);
      expect(ringCalls, ['get_state', 'get_state']);
      expect(
        eventGateway.createRequests.single.reminders.single.toEventJson(
          recurring: false,
        ),
        containsPair('methods', ['ring']),
      );
      await ringGateway.eventController.close();
    },
  );

  test(
    'permission failure preserves draft by stopping before create',
    () async {
      final eventGateway = _RecordingEventGateway();
      final ringGateway = FakeRingGateway(
        onGetState: () async => successInvocation(
          ringSnapshot(
            canEnableRing: false,
            blockingReasons: const [
              RingCapabilityBlockingReason.notificationPermissionUnavailable,
            ],
          ),
        ),
      );
      final timezoneGateway = FakeTimezoneGateway();
      final controller = CreateScheduleController(
        createEventUseCase: CreateEventUseCase(eventGateway),
        timezoneService: TimezoneApplicationService(timezoneGateway),
        ringGateway: ringGateway,
      );

      final result = await controller.submit(_ringDraft());

      expect(result.outcome, CreateScheduleSubmitOutcome.ringCapabilityFailure);
      expect(result.message, contains('通知权限不可用'));
      expect(eventGateway.createRequests, isEmpty);
      expect(timezoneGateway.resolveRequests, isEmpty);
      await ringGateway.eventController.close();
    },
  );

  test(
    'ring requires at least one reminder time before capability work',
    () async {
      final eventGateway = _RecordingEventGateway();
      final ringCalls = <String>[];
      final ringGateway = FakeRingGateway(
        callLog: ringCalls,
        onGetState: () async => successInvocation(ringSnapshot()),
      );
      final controller = CreateScheduleController(
        createEventUseCase: CreateEventUseCase(eventGateway),
        timezoneService: TimezoneApplicationService(FakeTimezoneGateway()),
        ringGateway: ringGateway,
      );
      final base = _ringDraft();

      final result = await controller.submit(
        CreateScheduleDraft(
          title: base.title,
          note: base.note,
          location: base.location,
          start: base.start,
          end: base.end,
          isAllDay: base.isAllDay,
          recurrence: base.recurrence,
          reminderAdvanceMinutes: const [],
          isRingingReminderEnabled: true,
        ),
      );

      expect(result.outcome, CreateScheduleSubmitOutcome.validationFailure);
      expect(result.message, '请先设置提醒时间再开启响铃');
      expect(ringCalls, isEmpty);
      expect(eventGateway.createRequests, isEmpty);
      await ringGateway.eventController.close();
    },
  );
}

CreateScheduleDraft _ringDraft() => const CreateScheduleDraft(
  title: '服药',
  note: '草稿内容应在权限失败后保留',
  location: '',
  start: LocalWallDateTime(
    year: 2026,
    month: 8,
    day: 22,
    hour: 9,
    minute: 0,
    second: 0,
  ),
  end: LocalWallDateTime(
    year: 2026,
    month: 8,
    day: 22,
    hour: 10,
    minute: 0,
    second: 0,
  ),
  isAllDay: false,
  recurrence: CreateScheduleRecurrence.once,
  reminderAdvanceMinutes: [15],
  isRingingReminderEnabled: true,
);

class _RecordingEventGateway implements EventNativeGateway {
  final List<CreateEventRequestDto> createRequests = [];

  @override
  Future<NativeInvocation<EventResponseDto>> createEvent(
    CreateEventRequestDto request,
  ) async {
    createRequests.add(request);
    return successInvocation(
      EventResponseDto(
        id: 'event-created',
        title: request.title,
        content: request.content,
        startAt: request.startAt,
        endAt: request.endAt,
        startDate: request.startDate,
        endDate: request.endDate,
        isAllDay: request.isAllDay,
        hasRecurrence: request.recurrence != null,
        status: 'active',
        recurrenceId: request.recurrence == null ? null : 'recurrence-created',
        recurrenceRevision: request.recurrence == null ? null : 1,
        categoryId: request.categoryId,
        importance: request.importance,
        location: request.location,
        timezone: request.timezone,
        source: request.source,
        createdAt: DateTime.utc(2026, 8, 9),
        updatedAt: DateTime.utc(2026, 8, 9),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
