import '../shared/contract_json_object.dart';
import 'notification_contract_enums.dart';

class RequestNotificationPermissionRequestDto {
  const RequestNotificationPermissionRequestDto({
    required this.requestNotificationPermission,
    required this.requestExactAlarmPermission,
    required this.source,
  });

  final bool requestNotificationPermission;
  final bool requestExactAlarmPermission;
  final NotificationPermissionRequestSource source;

  Map<String, dynamic> toJson() {
    if (!requestNotificationPermission && !requestExactAlarmPermission) {
      throw const FormatException(
        'At least one notification permission must be requested.',
      );
    }
    return {
      'request_notification_permission': requestNotificationPermission,
      'request_exact_alarm_permission': requestExactAlarmPermission,
      'source': source.wireValue,
    };
  }
}

class RequestNotificationPermissionResponseDto {
  const RequestNotificationPermissionResponseDto({
    required this.notificationPermission,
    required this.exactAlarmPermission,
    required this.canPostNotifications,
    required this.canScheduleExactAlarms,
    required this.shouldOpenSettings,
    this.message,
  });

  final NotificationPermissionStatus notificationPermission;
  final ExactAlarmPermissionStatus exactAlarmPermission;
  final bool canPostNotifications;
  final bool canScheduleExactAlarms;
  final bool shouldOpenSettings;
  final String? message;

  factory RequestNotificationPermissionResponseDto.fromJson(
    Map<String, dynamic> json,
  ) {
    ContractJsonObject.rejectUnknownKeys(json, {
      'notification_permission',
      'exact_alarm_permission',
      'can_post_notifications',
      'can_schedule_exact_alarms',
      'should_open_settings',
      'message',
    }, 'RequestNotificationPermissionResponse');
    ContractJsonObject.requireKeys(json, {
      'notification_permission',
      'exact_alarm_permission',
      'can_post_notifications',
      'can_schedule_exact_alarms',
      'should_open_settings',
    }, 'RequestNotificationPermissionResponse');
    final message = json['message'];
    if (message != null && message is! String) {
      throw const FormatException('message must be string or null.');
    }
    return RequestNotificationPermissionResponseDto(
      notificationPermission: NotificationPermissionStatus.fromWireValue(
        _readString(json, 'notification_permission'),
      ),
      exactAlarmPermission: ExactAlarmPermissionStatus.fromWireValue(
        _readString(json, 'exact_alarm_permission'),
      ),
      canPostNotifications: _readBool(json, 'can_post_notifications'),
      canScheduleExactAlarms: _readBool(json, 'can_schedule_exact_alarms'),
      shouldOpenSettings: _readBool(json, 'should_open_settings'),
      message: message as String?,
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
}
