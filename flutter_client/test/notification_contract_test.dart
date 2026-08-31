import 'dart:convert';
import 'dart:io';

import 'package:excellent_calendar/native_contract/common/native_result_dto.dart';
import 'package:excellent_calendar/native_contract/notification/notification_contract_enums.dart';
import 'package:excellent_calendar/native_contract/notification/notification_mapper.dart';
import 'package:excellent_calendar/native_contract/notification/notification_tap_payload_dto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('NativeResult parses notification success and failure envelopes', () {
    final success = NativeResultDto.fromJson({
      'ok': true,
      'data': {
        'notification_permission': 'granted',
        'exact_alarm_permission': 'granted',
        'can_post_notifications': true,
        'can_schedule_exact_alarms': true,
        'sdk_int': 35,
        'should_show_notification_rationale': false,
      },
      'error': null,
      'contract_version': 2,
      'request_id': 'permission-1',
    }, NotificationMapper.permissionStatus);
    final failure = NativeResultDto<Object>.fromJson({
      'ok': false,
      'data': null,
      'error': {
        'code': 'NOTIFICATION_PERMISSION_DENIED',
        'message': 'Permission denied.',
        'details': {'sdk_int': 35},
        'retryable': true,
      },
      'contract_version': 2,
      'request_id': 'permission-2',
    }, (raw) => raw as Object);

    expect(success.data!.canPostNotifications, isTrue);
    expect(success.requestId, 'permission-1');
    expect(failure.error!.code, 'NOTIFICATION_PERMISSION_DENIED');
    expect(failure.error!.details, {'sdk_int': 35});
  });

  test('NotificationTapPayload round-trips contract fields', () {
    final payload = NotificationTapPayloadDto.fromJson({
      'notification_id': '11111111-1111-4111-8111-111111111111',
      'delivery_id': '22222222-2222-4222-8222-222222222222',
      'delivery_attempt_id': '33333333-3333-4333-8333-333333333333',
      'kind': 'reminder',
      'reminder_id': '44444444-4444-4444-8444-444444444444',
      'recovery_batch_id': null,
      'target_type': 'event',
      'target_id': '55555555-5555-4555-8555-555555555555',
      'occurrence_key': null,
      'route': null,
      'opened_at': '2026-07-05T10:00:00.000Z',
    });

    expect(payload.targetType, NotificationTargetType.event);
    expect(payload.toJson(), {
      'notification_id': '11111111-1111-4111-8111-111111111111',
      'delivery_id': '22222222-2222-4222-8222-222222222222',
      'delivery_attempt_id': '33333333-3333-4333-8333-333333333333',
      'kind': 'reminder',
      'reminder_id': '44444444-4444-4444-8444-444444444444',
      'recovery_batch_id': null,
      'target_type': 'event',
      'target_id': '55555555-5555-4555-8555-555555555555',
      'occurrence_key': null,
      'route': null,
      'opened_at': '2026-07-05T10:00:00.000Z',
    });
  });

  test('Anniversary aggregate tap keeps typed occurrence identity', () {
    final payload = NotificationTapPayloadDto.fromJson({
      'notification_id': '11111111-1111-4111-8111-111111111111',
      'delivery_id': '22222222-2222-5222-8222-222222222222',
      'delivery_attempt_id': '33333333-3333-4333-8333-333333333333',
      'kind': 'anniversary_catch_up',
      'reminder_id': null,
      'recovery_batch_id': '44444444-4444-4444-8444-444444444444',
      'target_type': 'anniversary',
      'target_id': '55555555-5555-4555-8555-555555555555',
      'occurrence_key': '66666666-6666-5666-8666-666666666666',
      'route': 'anniversary.detail',
      'opened_at': '2026-08-31T02:05:00Z',
    });

    expect(payload.kind, NotificationKind.anniversaryCatchUp);
    expect(payload.targetType, NotificationTargetType.anniversary);
    expect(payload.occurrenceKey, '66666666-6666-5666-8666-666666666666');
  });

  test('Habit reminder tap requires occurrence identity and typed route', () {
    final payload = NotificationTapPayloadDto.fromJson({
      'notification_id': '11111111-1111-4111-8111-111111111111',
      'delivery_id': '22222222-2222-5222-8222-222222222222',
      'delivery_attempt_id': '33333333-3333-4333-8333-333333333333',
      'kind': 'reminder',
      'reminder_id': '44444444-4444-4444-8444-444444444444',
      'recovery_batch_id': null,
      'target_type': 'habit',
      'target_id': '55555555-5555-4555-8555-555555555555',
      'occurrence_key': '66666666-6666-5666-8666-666666666666',
      'route': 'habit.detail',
      'opened_at': '2026-08-28T02:05:00Z',
    });
    expect(payload.targetType, NotificationTargetType.habit);
    expect(payload.occurrenceKey, isNotNull);
    expect(
      () => NotificationTapPayloadDto.fromJson({
        ...payload.toJson(),
        'occurrence_key': null,
      }),
      throwsFormatException,
    );
  });

  test('Anniversary tap rejects missing occurrence and unknown kind', () {
    final base = <String, dynamic>{
      'notification_id': '11111111-1111-4111-8111-111111111111',
      'delivery_id': '22222222-2222-5222-8222-222222222222',
      'delivery_attempt_id': '33333333-3333-4333-8333-333333333333',
      'kind': 'reminder',
      'reminder_id': '44444444-4444-4444-8444-444444444444',
      'recovery_batch_id': null,
      'target_type': 'anniversary',
      'target_id': '55555555-5555-4555-8555-555555555555',
      'occurrence_key': null,
      'route': null,
      'opened_at': '2026-08-31T02:05:00Z',
    };
    expect(
      () => NotificationTapPayloadDto.fromJson(base),
      throwsFormatException,
    );
    expect(
      () => NotificationTapPayloadDto.fromJson({...base, 'kind': 'future'}),
      throwsFormatException,
    );
  });

  test(
    'ordinary Anniversary tap follows shared valid and invalid fixtures',
    () {
      Map<String, dynamic> fixture(String name) =>
          jsonDecode(
                File(
                  '../contracts/fixtures/anniversary/$name',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;

      final valid = NotificationTapPayloadDto.fromJson(
        fixture('ordinary_reminder_tap.valid.json'),
      );
      expect(valid.route, 'anniversary.detail');
      expect(
        () => NotificationTapPayloadDto.fromJson(
          fixture('ordinary_reminder_tap_missing_route.invalid.json'),
        ),
        throwsFormatException,
      );
    },
  );
}
