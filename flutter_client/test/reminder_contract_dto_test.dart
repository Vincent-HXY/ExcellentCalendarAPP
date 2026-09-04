import 'dart:convert';
import 'dart:io';

import 'package:excellent_calendar/native_contract/reminder/create_reminder_request_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/reminder_contract_enums.dart';
import 'package:excellent_calendar/native_contract/reminder/reminder_draft_request_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/reminder_response_dto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/reminder_fixtures.dart';

void main() {
  // 目的：锁定跨层请求的字段名和 wire value；方法：DTO 转 Map 后逐项检查 UTC 与枚举字符串。
  test('create request serializes UTC and ReminderMethod wire values', () {
    final request = CreateReminderRequestDto(
      targetType: ReminderTargetType.event,
      targetId: 'event-1',
      remindAt: DateTime.utc(2026, 6, 15, 2),
      methods: const [ReminderMethod.ring, ReminderMethod.wechat],
      source: ReminderSource.manual,
    );

    final json = request.toJson();

    expect(json['target_type'], 'event');
    expect(json['target_id'], 'event-1');
    expect(json['remind_at'], '2026-06-15T02:00:00.000Z');
    expect(json['methods'], ['ring', 'wechat']);
    expect(json['is_enabled'], isTrue);
    expect(json.containsKey('request_id'), isFalse);
  });

  // 目的：确保原生调度失败信息不会在 Dart 解析时丢失；方法：从 fixture 构造 DTO 并检查状态。
  test('response preserves failed scheduling state and failure reason', () {
    final response = ReminderResponseDto.fromJson(
      reminderResponseJson(
        status: 'failed',
        isEnabled: true,
        failureReason: 'Alarm registration failed.',
      ),
    );

    expect(response.status, ReminderStatus.failed);
    expect(response.failureReason, 'Alarm registration failed.');
    expect(response.methods, [ReminderMethod.ring]);
    expect(response.advanceDays, isNull);
    expect(response.templateKey, isNull);
  });

  test('response preserves event-completed cancellation reason', () {
    final response = ReminderResponseDto.fromJson(
      reminderResponseJson(
        status: 'cancelled',
        isEnabled: false,
        cancellationReason: 'event_completed',
        deletedAt: '2026-06-15T01:30:00.000Z',
      ),
    );

    expect(response.status, ReminderStatus.cancelled);
    expect(response.isEnabled, isFalse);
    expect(response.cancellationReason, 'event_completed');
  });

  test('response rejects unknown cancellation reason', () {
    expect(
      () => ReminderResponseDto.fromJson(
        reminderResponseJson(cancellationReason: 'unknown_reason'),
      ),
      throwsFormatException,
    );
  });

  test('response accepts Anniversary target projection and enum values', () {
    final json =
        reminderResponseJson(
            status: 'expired',
            isEnabled: false,
            cancellationReason: 'anniversary_template_disabled',
          )
          ..['target_type'] = 'anniversary'
          ..['target_id'] = '33333333-3333-4333-8333-333333333333'
          ..['occurrence_key'] = '44444444-4444-5444-8444-444444444444'
          ..['template_key'] = '55555555-5555-4555-8555-555555555555'
          ..['occurrence_date'] = '2026-09-04'
          ..['advance_days'] = 7
          ..['local_time'] = '09:00'
          ..['timezone_mode'] = 'follow_device'
          ..['advance_minutes'] = null
          ..['methods'] = ['popup']
          ..['scheduled_at'] = null
          ..['expiration_reason'] = 'anniversary_occurrence_elapsed'
          ..['expired_at'] = '2026-09-05T00:00:00Z';

    final response = ReminderResponseDto.fromJson(json);

    expect(response.advanceDays, 7);
    expect(response.occurrenceDate, '2026-09-04');
    expect(
      response.expirationReason,
      ReminderExpirationReason.anniversaryOccurrenceElapsed,
    );
    expect(
      response.lastCancellationReason,
      ReminderCancellationReason.anniversaryTemplateDisabled,
    );
  });

  test('response accepts Habit target projection and expiry', () {
    final json = reminderResponseJson(status: 'expired', isEnabled: false)
      ..['target_type'] = 'habit'
      ..['target_id'] = '33333333-3333-4333-8333-333333333333'
      ..['occurrence_key'] = '44444444-4444-5444-8444-444444444444'
      ..['template_key'] = '55555555-5555-4555-8555-555555555555'
      ..['occurrence_date'] = '2026-09-04'
      ..['local_time'] = '09:00'
      ..['timezone_mode'] = 'follow_device'
      ..['advance_minutes'] = null
      ..['methods'] = ['popup']
      ..['scheduled_at'] = null
      ..['expiration_reason'] = 'habit_occurrence_elapsed'
      ..['expired_at'] = '2026-09-05T00:00:00Z';

    final response = ReminderResponseDto.fromJson(json);

    expect(response.advanceDays, isNull);
    expect(
      response.expirationReason,
      ReminderExpirationReason.habitOccurrenceElapsed,
    );
  });

  test('response rejects target-specific fields on Event reminders', () {
    final json = reminderResponseJson()..['advance_days'] = 1;

    expect(() => ReminderResponseDto.fromJson(json), throwsFormatException);
  });

  test('response accepts canonical Contract fixtures for every target', () {
    const fixtures = {
      'ring/ordinary_popup_reminder.valid.json': ReminderTargetType.event,
      'anniversary/anniversary_reminder_pending.valid.json':
          ReminderTargetType.anniversary,
      'habit/habit_reminder_pending.valid.json': ReminderTargetType.habit,
    };

    for (final entry in fixtures.entries) {
      final json =
          jsonDecode(
                File('../contracts/fixtures/${entry.key}').readAsStringSync(),
              )
              as Map<String, dynamic>;

      expect(ReminderResponseDto.fromJson(json).targetType, entry.value);
    }
  });

  // 目的：验证随 Event 创建的提醒默认启用；方法：序列化 draft 并检查 is_enabled。
  test('embedded reminder draft is always created enabled', () {
    const draft = ReminderDraftRequestDto(
      targetType: 'event',
      advanceMinutes: 15,
      methods: ['popup'],
      source: 'manual',
    );

    expect(draft.toJson()['is_enabled'], isTrue);
  });
}
