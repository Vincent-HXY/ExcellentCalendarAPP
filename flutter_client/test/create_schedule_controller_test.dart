import 'package:excellent_calendar/application/event/create_event_use_case.dart';
import 'package:excellent_calendar/application/event/create_schedule_controller.dart';
import 'package:excellent_calendar/application/timezone/timezone_application_service.dart';
import 'package:excellent_calendar/gateway_interfaces/event_native_gateway.dart';
import 'package:excellent_calendar/native_contract/common/native_error_codes.dart';
import 'package:excellent_calendar/native_contract/common/native_error_dto.dart';
import 'package:excellent_calendar/native_contract/common/native_result_dto.dart';
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
        nowProvider: () => DateTime.utc(2026, 8, 1),
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
        nowProvider: () => DateTime.utc(2026, 8, 1),
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
        nowProvider: () => DateTime.utc(2026, 8, 1),
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

  test(
    'expired one-off reminder fails locally before Event creation',
    () async {
      final eventGateway = _RecordingEventGateway();
      final controller = CreateScheduleController(
        createEventUseCase: CreateEventUseCase(eventGateway),
        timezoneService: TimezoneApplicationService(FakeTimezoneGateway()),
        nowProvider: () => DateTime.utc(2026, 9, 1, 8),
      );

      final result = await controller.submit(
        const CreateScheduleDraft(
          title: '历史复盘',
          note: '',
          location: '',
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
          isAllDay: false,
          recurrence: CreateScheduleRecurrence.once,
          reminderAdvanceMinutes: [15],
          isRingingReminderEnabled: false,
        ),
      );

      expect(result.outcome, CreateScheduleSubmitOutcome.validationFailure);
      expect(result.message, '提醒时间已经失效，请调整日程时间或关闭提醒');
      expect(eventGateway.createRequests, isEmpty);
    },
  );

  test(
    'expired all-day one-off reminder fails locally before Event creation',
    () async {
      final eventGateway = _RecordingEventGateway();
      final timezoneGateway = FakeTimezoneGateway();
      final controller = CreateScheduleController(
        createEventUseCase: CreateEventUseCase(eventGateway),
        timezoneService: TimezoneApplicationService(timezoneGateway),
        nowProvider: () => DateTime.utc(2026, 9, 1, 8),
      );

      final result = await controller.submit(
        const CreateScheduleDraft(
          title: '历史全天复盘',
          note: '',
          location: '',
          start: LocalWallDateTime(
            year: 2026,
            month: 8,
            day: 31,
            hour: 0,
            minute: 0,
            second: 0,
          ),
          end: LocalWallDateTime(
            year: 2026,
            month: 9,
            day: 1,
            hour: 0,
            minute: 0,
            second: 0,
          ),
          isAllDay: true,
          recurrence: CreateScheduleRecurrence.once,
          reminderAdvanceMinutes: [15],
          isRingingReminderEnabled: false,
        ),
      );

      expect(result.outcome, CreateScheduleSubmitOutcome.validationFailure);
      expect(result.message, '提醒时间已经失效，请调整日程时间或关闭提醒');
      expect(timezoneGateway.resolveRequests, hasLength(1));
      expect(eventGateway.createRequests, isEmpty);
    },
  );

  test('all-day one-off reminder submits an absolute UTC instant', () async {
    final eventGateway = _RecordingEventGateway();
    final timezoneGateway = FakeTimezoneGateway();
    final controller = CreateScheduleController(
      createEventUseCase: CreateEventUseCase(eventGateway),
      timezoneService: TimezoneApplicationService(timezoneGateway),
      nowProvider: () => DateTime.utc(2026, 8, 1),
    );

    final result = await controller.submit(
      const CreateScheduleDraft(
        title: '全天纪要',
        note: '',
        location: '',
        start: LocalWallDateTime(
          year: 2026,
          month: 8,
          day: 22,
          hour: 0,
          minute: 0,
          second: 0,
        ),
        end: LocalWallDateTime(
          year: 2026,
          month: 8,
          day: 23,
          hour: 0,
          minute: 0,
          second: 0,
        ),
        isAllDay: true,
        recurrence: CreateScheduleRecurrence.once,
        reminderAdvanceMinutes: [15],
        isRingingReminderEnabled: false,
      ),
    );

    expect(result.succeeded, isTrue);
    expect(timezoneGateway.resolveRequests, hasLength(1));
    expect(
      timezoneGateway.resolveRequests.single.localDateTime,
      const LocalWallDateTime(
        year: 2026,
        month: 8,
        day: 22,
        hour: 0,
        minute: 0,
        second: 0,
      ),
    );
    expect(
      eventGateway.createRequests.single.reminders.single.toEventJson(
        recurring: false,
      ),
      containsPair('remind_at', '2026-08-21T23:45:00.000Z'),
    );
    expect(
      eventGateway.createRequests.single.reminders.single.toEventJson(
        recurring: false,
      ),
      containsPair('advance_minutes', null),
    );
  });

  test('timezone read failure is localized without Native details', () async {
    final controller = CreateScheduleController(
      createEventUseCase: CreateEventUseCase(_RecordingEventGateway()),
      timezoneService: TimezoneApplicationService(
        FakeTimezoneGateway(
          deviceFailure: failureInvocation(
            code: NativeErrorCodes.timezoneDatabaseUnavailable,
            message: 'native timezone detail',
          ),
        ),
      ),
    );

    final result = await controller.refreshDeviceTimezone();

    expect(result.succeeded, isFalse);
    expect(result.errorMessage, '系统时区数据暂不可用，请稍后重试');
    expect(
      result.errorMessage,
      isNot(contains('TIMEZONE_DATABASE_UNAVAILABLE')),
    );
    expect(result.errorMessage, isNot(contains('native timezone detail')));
  });

  test(
    'timezone resolution failure is localized without Native details',
    () async {
      final eventGateway = _RecordingEventGateway();
      final controller = CreateScheduleController(
        createEventUseCase: CreateEventUseCase(eventGateway),
        timezoneService: TimezoneApplicationService(
          FakeTimezoneGateway(
            resolveFailure: failureInvocation(
              code: NativeErrorCodes.timezoneIdInvalid,
              message: 'native resolution detail',
            ),
          ),
        ),
        nowProvider: () => DateTime.utc(2026, 8, 1),
      );

      final result = await controller.submit(_popupDraft());

      expect(result.outcome, CreateScheduleSubmitOutcome.timezoneFailure);
      expect(result.message, '设备时区无效，请检查系统时区设置');
      expect(result.message, isNot(contains('TIMEZONE_ID_INVALID')));
      expect(result.message, isNot(contains('native resolution detail')));
      expect(eventGateway.createRequests, isEmpty);
    },
  );

  test('ring capability failure is localized without Native details', () async {
    final ringGateway = FakeRingGateway(
      onGetState: () async => failureInvocation(
        code: NativeErrorCodes.ringCapabilityUnavailable,
        message: 'native ring detail',
      ),
    );
    final controller = CreateScheduleController(
      createEventUseCase: CreateEventUseCase(_RecordingEventGateway()),
      timezoneService: TimezoneApplicationService(FakeTimezoneGateway()),
      ringGateway: ringGateway,
    );

    final result = await controller.checkRingCapability();

    expect(result.canEnable, isFalse);
    expect(result.message, '当前设备暂时无法启用响铃提醒');
    expect(result.message, isNot(contains('RING_CAPABILITY_UNAVAILABLE')));
    expect(result.message, isNot(contains('native ring detail')));
    await ringGateway.eventController.close();
  });

  test(
    'Native reminder failure is localized without code or request id',
    () async {
      final eventGateway = _RecordingEventGateway(
        failure: NativeInvocation<EventResponseDto>(
          rawResponse: const {},
          result: const NativeResultDto<EventResponseDto>(
            ok: false,
            data: null,
            error: NativeErrorDto(
              code: NativeErrorCodes.reminderTimeInvalid,
              message: 'Reminder time is invalid',
            ),
            contractVersion: 2,
            requestId: 'native-request-secret',
          ),
          isNativeResult: true,
        ),
      );
      final controller = CreateScheduleController(
        createEventUseCase: CreateEventUseCase(eventGateway),
        timezoneService: TimezoneApplicationService(FakeTimezoneGateway()),
        nowProvider: () => DateTime.utc(2026, 8, 1),
      );

      final result = await controller.submit(_popupDraft());

      expect(result.outcome, CreateScheduleSubmitOutcome.nativeFailure);
      expect(result.message, '提醒时间已经失效，请调整日程时间或关闭提醒');
      expect(result.message, isNot(contains('REMINDER_TIME_INVALID')));
      expect(result.message, isNot(contains('native-request-secret')));
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

CreateScheduleDraft _popupDraft() => const CreateScheduleDraft(
  title: '未来安排',
  note: '',
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
  isRingingReminderEnabled: false,
);

class _RecordingEventGateway implements EventNativeGateway {
  _RecordingEventGateway({this.failure});

  final NativeInvocation<EventResponseDto>? failure;
  final List<CreateEventRequestDto> createRequests = [];

  @override
  Future<NativeInvocation<EventResponseDto>> createEvent(
    CreateEventRequestDto request,
  ) async {
    createRequests.add(request);
    if (failure != null) return failure!;
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
