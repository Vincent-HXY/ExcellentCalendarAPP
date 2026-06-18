import 'package:excellent_calendar/native_contract/reminder/create_reminder_request_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/reminder_contract_enums.dart';
import 'package:excellent_calendar/native_contract/reminder/reminder_response_dto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/reminder_fixtures.dart';

void main() {
  test('create request serializes UTC and ReminderMethod wire values', () {
    final request = CreateReminderRequestDto(
      targetType: ReminderTargetType.event,
      targetId: 'event-1',
      remindAt: DateTime(2026, 6, 15, 10),
      methods: const [ReminderMethod.ring, ReminderMethod.wechat],
      isEnabled: true,
      source: ReminderSource.manual,
    );

    final json = request.toJson();

    expect(json['target_type'], 'event');
    expect(json['target_id'], 'event-1');
    expect(
      json['remind_at'],
      DateTime(2026, 6, 15, 10).toUtc().toIso8601String(),
    );
    expect(json['methods'], ['ring', 'wechat']);
    expect(json.containsKey('request_id'), isFalse);
  });

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
}
