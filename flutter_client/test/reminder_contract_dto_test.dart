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
    expect(response.methods, [ReminderMethod.ring, ReminderMethod.popup]);
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
