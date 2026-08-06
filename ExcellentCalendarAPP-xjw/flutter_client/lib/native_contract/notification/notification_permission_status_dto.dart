import '../shared/contract_json_object.dart';
import 'notification_contract_enums.dart';

class NotificationPermissionStatusDto {
  const NotificationPermissionStatusDto({
    required this.notificationPermission,
    required this.exactAlarmPermission,
    required this.canPostNotifications,
    required this.canScheduleExactAlarms,
    required this.sdkInt,
    required this.shouldShowNotificationRationale,
  });

  final NotificationPermissionStatus notificationPermission;
  final ExactAlarmPermissionStatus exactAlarmPermission;
  final bool canPostNotifications;
  final bool canScheduleExactAlarms;
  final int sdkInt;
  final bool shouldShowNotificationRationale;

  factory NotificationPermissionStatusDto.fromJson(Map<String, dynamic> json) {
    ContractJsonObject.rejectUnknownKeys(json, {
      'notification_permission',
      'exact_alarm_permission',
      'can_post_notifications',
      'can_schedule_exact_alarms',
      'sdk_int',
      'should_show_notification_rationale',
    }, 'NotificationPermissionStatusResponse');
    ContractJsonObject.requireKeys(json, {
      'notification_permission',
      'exact_alarm_permission',
      'can_post_notifications',
      'can_schedule_exact_alarms',
      'sdk_int',
      'should_show_notification_rationale',
    }, 'NotificationPermissionStatusResponse');
    return NotificationPermissionStatusDto(
      notificationPermission: NotificationPermissionStatus.fromWireValue(
        _readString(json, 'notification_permission'),
      ),
      exactAlarmPermission: ExactAlarmPermissionStatus.fromWireValue(
        _readString(json, 'exact_alarm_permission'),
      ),
      canPostNotifications: _readBool(json, 'can_post_notifications'),
      canScheduleExactAlarms: _readBool(json, 'can_schedule_exact_alarms'),
      sdkInt: _readPositiveInt(json, 'sdk_int'),
      shouldShowNotificationRationale: _readBool(
        json,
        'should_show_notification_rationale',
      ),
    );
  }

  static String _readString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String) return value;
    throw FormatException('$key must be string.');
  }

  static bool _readBool(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is bool) return value;
    throw FormatException('$key must be bool.');
  }

  static int _readPositiveInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int && value >= 1) return value;
    throw FormatException('$key must be positive integer.');
  }
}
