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
      'notification_id': 'notification-1',
      'delivery_id': 'delivery-1',
      'delivery_attempt_id': 'attempt-1',
      'kind': 'reminder',
      'reminder_id': 'reminder-1',
      'recovery_batch_id': null,
      'target_type': 'event',
      'target_id': 'event-1',
      'occurrence_key': null,
      'route': null,
      'opened_at': '2026-07-05T10:00:00.000Z',
    });

    expect(payload.targetType, NotificationTargetType.event);
    expect(payload.toJson(), {
      'notification_id': 'notification-1',
      'delivery_id': 'delivery-1',
      'delivery_attempt_id': 'attempt-1',
      'kind': 'reminder',
      'reminder_id': 'reminder-1',
      'recovery_batch_id': null,
      'target_type': 'event',
      'target_id': 'event-1',
      'occurrence_key': null,
      'route': null,
      'opened_at': '2026-07-05T10:00:00.000Z',
    });
  });
}
