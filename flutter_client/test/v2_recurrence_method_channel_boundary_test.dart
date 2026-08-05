import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_event_adapter.dart';
import 'package:excellent_calendar/native_contract/common/native_result_dto.dart';
import 'package:excellent_calendar/native_contract/event/create_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/delete_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_occurrence_operation_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_series_operation_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/get_event_detail_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/list_event_occurrences_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/update_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/recurrence/recurrence_rule_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/recurring_reminder_draft_request_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/reminder_contract_enums.dart';
import 'package:excellent_calendar/native_contract/reminder/reminder_draft_request_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/reminder_response_dto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('excellent_calendar/native');
const _eventId = '11111111-1111-4111-8111-111111111111';
const _recurrenceId = '22222222-2222-4222-8222-222222222222';
const _occurrenceKey = '33333333-3333-4333-8333-333333333333';
const _reminderId = '44444444-4444-4444-8444-444444444444';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('recurring create sends intent only and a popup template', () {
    final json = CreateEventRequestDto.timed(
      title: 'London stand-up',
      startAt: DateTime.utc(2026, 3, 28, 9),
      endAt: DateTime.utc(2026, 3, 28, 10),
      timezone: 'Europe/London',
      source: 'manual',
      recurrence: const RecurrenceRuleDto(frequency: 'monthly'),
      reminders: const [RecurringReminderDraftRequestDto(advanceMinutes: 30)],
    ).toJson();

    expect(json['start_at'], '2026-03-28T09:00:00Z');
    expect(json['timezone'], 'Europe/London');
    expect(json['recurrence'], {
      'frequency': 'monthly',
      'interval': 1,
      'end_at': null,
      'count': null,
    });
    expect(json['recurrence'], isNot(contains('start_at')));
    expect(json['recurrence'], isNot(contains('timezone')));
    expect(json['recurrence'], isNot(contains('day_of_month')));
    expect(json['recurrence'], isNot(contains('days_of_week')));
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
    expect((json['reminders'] as List).single, isNot(contains('remind_at')));
  });

  test('recurrence DTO rejects custom interval and finite series', () {
    expect(
      () => const RecurrenceRuleDto(frequency: 'daily', interval: 2).toJson(),
      throwsFormatException,
    );
    expect(
      () => RecurrenceRuleDto(
        frequency: 'weekly',
        endAt: DateTime.utc(2026, 12, 31),
      ).toJson(),
      throwsFormatException,
    );
    expect(
      () => const RecurrenceRuleDto(frequency: 'monthly', count: 10).toJson(),
      throwsFormatException,
    );
  });

  test(
    'recurring all-day and non-popup reminder combinations are rejected',
    () {
      expect(
        () => const CreateEventRequestDto.allDay(
          title: 'All day series',
          startDate: '2026-08-05',
          endDate: '2026-08-06',
          timezone: 'Asia/Shanghai',
          source: 'manual',
          recurrence: RecurrenceRuleDto(frequency: 'daily'),
          reminders: [RecurringReminderDraftRequestDto(advanceMinutes: 15)],
        ).toJson(),
        throwsFormatException,
      );
      expect(
        () => CreateEventRequestDto.timed(
          title: 'Ring series',
          startAt: DateTime.utc(2026, 8, 5, 1),
          endAt: DateTime.utc(2026, 8, 5, 2),
          timezone: 'Asia/Shanghai',
          source: 'manual',
          recurrence: const RecurrenceRuleDto(frequency: 'daily'),
          reminders: const [
            ReminderDraftRequestDto(
              targetType: 'event',
              advanceMinutes: 15,
              methods: ['ring'],
              source: 'manual',
            ),
          ],
        ).toJson(),
        throwsFormatException,
      );
    },
  );

  test('recurring update uses expected revision for reminder context', () {
    final json = const UpdateEventRequestDto(
      id: _eventId,
      expectedRecurrenceRevision: 3,
      reminders: [RecurringReminderDraftRequestDto(advanceMinutes: 20)],
    ).toJson();

    expect(json['expected_recurrence_revision'], 3);
    expect(json['reminders'], [
      {
        'target_type': 'event',
        'target_id': null,
        'advance_minutes': 20,
        'methods': ['popup'],
        'message': null,
        'is_enabled': true,
        'source': 'manual',
      },
    ]);
  });

  test(
    'query ranges allow fractions but occurrence identity is whole-second',
    () {
      final range = ListEventOccurrencesRequestDto.timed(
        eventId: _eventId,
        recurrenceRevision: 3,
        rangeStartAt: DateTime.utc(2026, 8, 5, 1, 0, 0, 123),
        rangeEndAt: DateTime.utc(2026, 8, 6, 1, 0, 0, 456),
      ).toJson();

      expect(range['range_start_at'], '2026-08-05T01:00:00.123Z');
      expect(range['range_end_at'], '2026-08-06T01:00:00.456Z');
      expect(
        () => EventOccurrenceOperationRequestDto.timed(
          eventId: _eventId,
          recurrenceRevision: 3,
          occurrenceKey: _occurrenceKey,
          occurrenceStartAt: DateTime.utc(2026, 8, 5, 1, 0, 0, 1),
        ).toJson(),
        throwsFormatException,
      );
    },
  );

  test('NativeResult rejects non-V2 envelopes', () {
    expect(
      () => NativeResultDto<Object?>.fromJson(const {
        'ok': true,
        'data': null,
        'error': null,
        'contract_version': 1,
      }, (data) => data),
      throwsFormatException,
    );
  });

  test('adapter preserves yearly and revision business errors', () async {
    var invocationCount = 0;
    MethodCall? yearlyCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          invocationCount += 1;
          if (invocationCount == 1) yearlyCall = call;
          return _failureEnvelope(
            invocationCount == 1
                ? 'FEATURE_NOT_IMPLEMENTED'
                : 'RECURRENCE_REVISION_CONFLICT',
          );
        });

    final adapter = MethodChannelEventAdapter(channel: _channel);
    final yearly = await adapter.createEvent(
      CreateEventRequestDto.timed(
        title: 'Yearly preview',
        startAt: DateTime.utc(2026, 8, 5, 1),
        endAt: DateTime.utc(2026, 8, 5, 2),
        timezone: 'Asia/Shanghai',
        source: 'manual',
        recurrence: const RecurrenceRuleDto(frequency: 'yearly'),
      ),
    );
    final conflict = await adapter.updateEvent(
      const UpdateEventRequestDto(
        id: _eventId,
        expectedRecurrenceRevision: 2,
        title: 'Stale update',
      ),
    );

    expect(yearly.isNativeResult, isTrue);
    expect(yearly.result.error!.code, 'FEATURE_NOT_IMPLEMENTED');
    expect(yearlyCall!.arguments['recurrence']['frequency'], 'yearly');
    expect(conflict.isNativeResult, isTrue);
    expect(conflict.result.error!.code, 'RECURRENCE_REVISION_CONFLICT');
  });

  test(
    'event adapter exposes the complete recurring V2 method surface',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            calls.add(call);
            final data = switch (call.method) {
              'event.detail' => _eventDetailJson(),
              'event.list_occurrences' => {
                'items': [_occurrenceJson()],
                'has_more': false,
                'next_cursor': null,
              },
              'event_occurrence.complete' ||
              'event_occurrence.reopen' ||
              'event_occurrence.skip' ||
              'event_occurrence.cancel' => _occurrenceStateJson(),
              _ => _eventJson(),
            };
            return _successEnvelope(data, requestId: 'call-${calls.length}');
          });

      final adapter = MethodChannelEventAdapter(channel: _channel);
      final createRequest = CreateEventRequestDto.timed(
        title: 'Daily review',
        startAt: DateTime.utc(2026, 8, 5, 1),
        endAt: DateTime.utc(2026, 8, 5, 2),
        timezone: 'Asia/Shanghai',
        source: 'manual',
        recurrence: const RecurrenceRuleDto(frequency: 'daily'),
        reminders: const [RecurringReminderDraftRequestDto(advanceMinutes: 15)],
      );
      final occurrenceRequest = EventOccurrenceOperationRequestDto.timed(
        eventId: _eventId,
        recurrenceRevision: 3,
        occurrenceKey: _occurrenceKey,
        occurrenceStartAt: _occurrenceStart,
      );
      const seriesRequest = EventSeriesOperationRequestDto(
        eventId: _eventId,
        recurrenceRevision: 3,
      );

      await adapter.createEvent(createRequest);
      await adapter.updateEvent(
        const UpdateEventRequestDto(
          id: _eventId,
          expectedRecurrenceRevision: 3,
          title: 'Updated daily review',
        ),
      );
      await adapter.getEventDetail(
        const GetEventDetailRequestDto(id: _eventId),
      );
      await adapter.listOccurrences(
        ListEventOccurrencesRequestDto.timed(
          eventId: _eventId,
          recurrenceRevision: 3,
          rangeStartAt: _occurrenceStart,
          rangeEndAt: _occurrenceRangeEnd,
        ),
      );
      await adapter.completeOccurrence(occurrenceRequest);
      await adapter.reopenOccurrence(occurrenceRequest);
      await adapter.skipOccurrence(occurrenceRequest);
      await adapter.cancelOccurrence(occurrenceRequest);
      await adapter.completeSeries(seriesRequest);
      await adapter.reopenSeries(seriesRequest);
      await adapter.cancelSeries(seriesRequest);
      await adapter.deleteEvent(
        const DeleteEventRequestDto(
          id: _eventId,
          recurrenceDeleteScope: 'all_occurrences',
          expectedRecurrenceRevision: 3,
        ),
      );

      expect(calls.map((call) => call.method), [
        'event.create',
        'event.update',
        'event.detail',
        'event.list_occurrences',
        'event_occurrence.complete',
        'event_occurrence.reopen',
        'event_occurrence.skip',
        'event_occurrence.cancel',
        'event.complete_series',
        'event.reopen_series',
        'event.cancel_series',
        'event.delete',
      ]);
      expect(calls[4].arguments, {
        'event_id': _eventId,
        'recurrence_revision': 3,
        'occurrence_key': _occurrenceKey,
        'occurrence_start_at': '2026-08-05T01:00:00Z',
        'occurrence_start_date': null,
      });
      expect(calls.last.arguments, {
        'id': _eventId,
        'delete_mode': 'soft',
        'recurrence_delete_scope': 'all_occurrences',
        'expected_recurrence_revision': 3,
        'reason': null,
      });
    },
  );

  test('expired rolling reminder preserves occurrence identity', () {
    final response = ReminderResponseDto.fromJson(
      _recurringReminderJson(
        status: 'expired',
        isEnabled: false,
        scheduledAt: null,
        expirationReason: 'recovery_window_elapsed',
        expiredAt: '2026-08-05T02:00:00Z',
      ),
    );

    expect(response.status, ReminderStatus.expired);
    expect(response.isRecurring, isTrue);
    expect(response.recurrenceRevision, 3);
    expect(response.occurrenceKey, _occurrenceKey);
    expect(
      response.expirationReason,
      ReminderExpirationReason.recoveryWindowElapsed,
    );
  });
}

final _occurrenceStart = DateTime.utc(2026, 8, 5, 1);
final _occurrenceRangeEnd = DateTime.utc(2026, 8, 12, 1);

Map<String, dynamic> _successEnvelope(
  Object? data, {
  required String requestId,
}) => {
  'ok': true,
  'data': data,
  'error': null,
  'contract_version': 2,
  'request_id': requestId,
};

Map<String, dynamic> _failureEnvelope(String code) => {
  'ok': false,
  'data': null,
  'error': {
    'code': code,
    'message': 'Expected V2 business failure.',
    'details': null,
    'retryable': false,
  },
  'contract_version': 2,
  'request_id': 'failure-1',
};

Map<String, dynamic> _eventJson() => {
  'id': _eventId,
  'title': 'Daily review',
  'content': null,
  'start_at': '2026-08-05T01:00:00Z',
  'end_at': '2026-08-05T02:00:00Z',
  'start_date': null,
  'end_date': null,
  'is_all_day': false,
  'has_recurrence': true,
  'status': 'active',
  'completed_at': null,
  'recurrence_id': _recurrenceId,
  'recurrence_revision': 3,
  'category_id': null,
  'importance': 'unimportant_noturgent',
  'location': null,
  'timezone': 'Asia/Shanghai',
  'source': 'manual',
  'created_at': '2026-08-01T00:00:00Z',
  'updated_at': '2026-08-05T00:00:00Z',
  'deleted_at': null,
};

Map<String, dynamic> _recurrenceJson() => {
  'recurrence_id': _recurrenceId,
  'revision': 3,
  'frequency': 'daily',
  'interval': 1,
  'start_at': '2026-08-05T01:00:00Z',
  'start_date': null,
  'timezone': 'Asia/Shanghai',
  'day_of_month': null,
  'days_of_week': <int>[],
  'month_of_year': null,
  'end_at': null,
  'count': null,
  'created_at': '2026-08-01T00:00:00Z',
};

Map<String, dynamic> _eventDetailJson() => {
  'event': _eventJson(),
  'recurrence': _recurrenceJson(),
  'reminders': [_recurringReminderJson()],
  'category': null,
};

Map<String, dynamic> _occurrenceJson() => {
  'event_id': _eventId,
  'recurrence_revision': 3,
  'occurrence_key': _occurrenceKey,
  'occurrence_start_at': '2026-08-05T01:00:00Z',
  'occurrence_end_at': '2026-08-05T02:00:00Z',
  'occurrence_start_date': null,
  'occurrence_end_date': null,
  'timezone': 'Asia/Shanghai',
  'state': null,
};

Map<String, dynamic> _occurrenceStateJson() => {
  'event_id': _eventId,
  'recurrence_revision': 3,
  'occurrence_key': _occurrenceKey,
  'occurrence_start_at': '2026-08-05T01:00:00Z',
  'occurrence_start_date': null,
  'status': 'completed',
  'state_changed_at': '2026-08-05T02:05:00Z',
  'reopened_at': null,
  'created_at': '2026-08-05T02:05:00Z',
  'updated_at': '2026-08-05T02:05:00Z',
};

Map<String, dynamic> _recurringReminderJson({
  String status = 'scheduled',
  bool isEnabled = true,
  String? scheduledAt = '2026-08-05T00:00:00Z',
  String? expirationReason,
  String? expiredAt,
}) => {
  'reminder_id': _reminderId,
  'target_type': 'event',
  'target_id': _eventId,
  'recurrence_revision': 3,
  'occurrence_key': _occurrenceKey,
  'occurrence_start_at': '2026-08-05T01:00:00Z',
  'remind_at': '2026-08-05T00:45:00Z',
  'advance_minutes': 15,
  'methods': ['popup'],
  'message': null,
  'is_enabled': isEnabled,
  'status': status,
  'scheduled_at': scheduledAt,
  'last_triggered_at': null,
  'failure_reason': null,
  'last_cancellation_reason': null,
  'last_cancelled_at': null,
  'expiration_reason': expirationReason,
  'expired_at': expiredAt,
  'reactivated_at': null,
  'reactivation_count': 0,
  'created_at': '2026-08-01T00:00:00Z',
  'updated_at': '2026-08-05T00:00:00Z',
  'deleted_at': null,
};
