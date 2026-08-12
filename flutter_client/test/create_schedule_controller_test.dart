import 'package:excellent_calendar/application/event/create_event_use_case.dart';
import 'package:excellent_calendar/application/event/create_schedule_controller.dart';
import 'package:excellent_calendar/application/timezone/timezone_application_service.dart';
import 'package:excellent_calendar/gateway_interfaces/event_native_gateway.dart';
import 'package:excellent_calendar/native_contract/event/create_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_response_dto.dart';
import 'package:excellent_calendar/native_contract/runtime/local_wall_date_time.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_timezone_gateway.dart';
import 'fixtures/notification_fixtures.dart';

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
}

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
