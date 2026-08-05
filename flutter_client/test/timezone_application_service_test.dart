import 'package:excellent_calendar/application/timezone/timezone_application_service.dart';
import 'package:excellent_calendar/native_contract/event/event_occurrence_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_response_dto.dart';
import 'package:excellent_calendar/native_contract/runtime/local_wall_date_time.dart';
import 'package:excellent_calendar/native_contract/runtime/resolve_local_datetime_dto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_timezone_gateway.dart';

void main() {
  test('fake gateway covers London gap and fold resolution branches', () async {
    final gateway = FakeTimezoneGateway(
      resolve: (request) {
        return switch (request.localDateTime.toString()) {
          '2026-03-29T01:30:00' => ResolveLocalDateTimeResponseDto(
            requestedLocalDateTime: request.localDateTime,
            resolvedLocalDateTime: LocalWallDateTime.parse(
              '2026-03-29T02:00:00',
            ),
            utcInstant: DateTime.parse('2026-03-29T01:00:00Z'),
            timezone: request.timezone,
            resolution: LocalDateTimeResolution.gapShifted,
          ),
          '2026-10-25T01:30:00' => ResolveLocalDateTimeResponseDto(
            requestedLocalDateTime: request.localDateTime,
            resolvedLocalDateTime: request.localDateTime,
            utcInstant: DateTime.parse('2026-10-25T00:30:00Z'),
            timezone: request.timezone,
            resolution: LocalDateTimeResolution.foldEarlier,
          ),
          _ => throw StateError('Unexpected local time'),
        };
      },
    );
    final service = TimezoneApplicationService(gateway);

    final gap = await service.resolveLocalDateTime(
      localDateTime: LocalWallDateTime.parse('2026-03-29T01:30:00'),
      timezone: 'Europe/London',
    );
    final fold = await service.resolveLocalDateTime(
      localDateTime: LocalWallDateTime.parse('2026-10-25T01:30:00'),
      timezone: 'Europe/London',
    );

    expect(gap.result.data!.resolution, LocalDateTimeResolution.gapShifted);
    expect(
      gap.result.data!.resolvedLocalDateTime.toString(),
      '2026-03-29T02:00:00',
    );
    expect(fold.result.data!.resolution, LocalDateTimeResolution.foldEarlier);
    expect(
      fold.result.data!.utcInstant,
      DateTime.parse('2026-10-25T00:30:00Z'),
    );
  });

  test('device timezone is read again instead of cached', () async {
    final gateway = FakeTimezoneGateway(
      deviceTimezones: const ['Europe/London', 'Asia/Shanghai'],
    );
    final service = TimezoneApplicationService(gateway);

    expect(
      (await service.getDeviceTimezone()).result.data!.timezone,
      'Europe/London',
    );
    expect(
      (await service.getDeviceTimezone()).result.data!.timezone,
      'Asia/Shanghai',
    );
  });

  test(
    'Event and occurrence UTC ranges use batched original-timezone localization',
    () async {
      final gateway = FakeTimezoneGateway(
        localize: (request) => request.instants
            .map((instant) {
              if (instant == DateTime.parse('2026-03-29T00:30:00Z')) {
                return LocalWallDateTime.parse('2026-03-29T00:30:00');
              }
              if (instant == DateTime.parse('2026-03-29T01:00:00Z')) {
                return LocalWallDateTime.parse('2026-03-29T02:00:00');
              }
              return LocalWallDateTime.parse('2026-03-29T03:00:00');
            })
            .toList(growable: false),
      );
      final service = TimezoneApplicationService(gateway);
      final first = _event(
        id: 'event-1',
        startAt: '2026-03-29T00:30:00Z',
        endAt: '2026-03-29T01:00:00Z',
      );
      final second = _event(
        id: 'event-2',
        startAt: '2026-03-29T01:00:00Z',
        endAt: '2026-03-29T02:00:00Z',
      );

      final events = await service.localizeEventTimes([first, second]);

      expect(events.ok, isTrue);
      expect(gateway.localizeRequests, hasLength(1));
      expect(gateway.localizeRequests.single.instants, [
        DateTime.parse('2026-03-29T00:30:00Z'),
        DateTime.parse('2026-03-29T01:00:00Z'),
        DateTime.parse('2026-03-29T01:00:00Z'),
        DateTime.parse('2026-03-29T02:00:00Z'),
      ]);
      expect(events.ranges['event-1']!.end.toString(), '2026-03-29T02:00:00');
      expect(events.ranges['event-2']!.start.toString(), '2026-03-29T02:00:00');
      expect(events.ranges['event-1']!.timezone, 'Europe/London');

      final occurrences = await service.localizeOccurrenceTimes([
        EventOccurrenceResponseDto(
          eventId: 'event-1',
          recurrenceRevision: 1,
          occurrenceKey: 'occurrence-1',
          occurrenceStartAt: DateTime.parse('2026-03-29T00:30:00Z'),
          occurrenceEndAt: DateTime.parse('2026-03-29T01:00:00Z'),
          occurrenceStartDate: null,
          occurrenceEndDate: null,
          timezone: 'Europe/London',
          state: null,
        ),
      ]);
      expect(occurrences.ok, isTrue);
      expect(
        occurrences.ranges['occurrence-1']!.end.toString(),
        '2026-03-29T02:00:00',
      );
      expect(gateway.localizeRequests, hasLength(2));
    },
  );

  test(
    'mixed Events are batched separately by their original timezone',
    () async {
      final gateway = FakeTimezoneGateway(
        localize: (request) {
          final hour = request.timezone == 'Europe/London' ? 10 : 18;
          return [
            LocalWallDateTime(
              year: 2026,
              month: 2,
              day: 1,
              hour: hour,
              minute: 0,
              second: 0,
            ),
            LocalWallDateTime(
              year: 2026,
              month: 2,
              day: 1,
              hour: hour + 1,
              minute: 0,
              second: 0,
            ),
          ];
        },
      );
      final service = TimezoneApplicationService(gateway);

      final result = await service.localizeEventTimes([
        _event(
          id: 'london',
          startAt: '2026-02-01T10:00:00Z',
          endAt: '2026-02-01T11:00:00Z',
        ),
        _event(
          id: 'shanghai',
          startAt: '2026-02-01T10:00:00Z',
          endAt: '2026-02-01T11:00:00Z',
          timezone: 'Asia/Shanghai',
        ),
      ]);

      expect(result.ok, isTrue);
      expect(gateway.localizeRequests.map((request) => request.timezone), [
        'Europe/London',
        'Asia/Shanghai',
      ]);
      expect(result.ranges['london']!.start.hour, 10);
      expect(result.ranges['shanghai']!.start.hour, 18);
    },
  );
}

EventResponseDto _event({
  required String id,
  required String startAt,
  required String endAt,
  String timezone = 'Europe/London',
}) {
  return EventResponseDto(
    id: id,
    title: id,
    startAt: DateTime.parse(startAt),
    endAt: DateTime.parse(endAt),
    startDate: null,
    endDate: null,
    isAllDay: false,
    hasRecurrence: false,
    status: 'active',
    recurrenceId: null,
    recurrenceRevision: null,
    timezone: timezone,
    source: 'manual',
    createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
    updatedAt: DateTime.parse('2026-01-01T00:00:00Z'),
  );
}
