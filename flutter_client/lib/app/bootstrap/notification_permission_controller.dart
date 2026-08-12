import '../../gateway_interfaces/notification_native_gateway.dart';
import '../../native_contract/notification/notification_contract_enums.dart';
import '../../native_contract/notification/notification_permission_status_dto.dart';
import '../../native_contract/notification/open_notification_settings_request_dto.dart';
import '../../native_contract/notification/request_notification_permission_dto.dart';

class NotificationPermissionRefreshResult {
  const NotificationPermissionRefreshResult.success(this.status)
    : errorMessage = null;

  const NotificationPermissionRefreshResult.failure(this.errorMessage)
    : status = null;

  final NotificationPermissionStatusDto? status;
  final String? errorMessage;

  bool get succeeded => status != null;
}

class NotificationPermissionRequestResult {
  const NotificationPermissionRequestResult.success({
    required this.shouldOpenSettings,
    required this.message,
  }) : errorMessage = null;

  const NotificationPermissionRequestResult.failure(this.errorMessage)
    : shouldOpenSettings = false,
      message = null;

  final bool shouldOpenSettings;
  final String? message;
  final String? errorMessage;

  bool get succeeded => errorMessage == null;
}

class NotificationPermissionController {
  const NotificationPermissionController(this._gateway);

  final NotificationNativeGateway _gateway;

  Future<NotificationPermissionRefreshResult> refresh() async {
    final invocation = await _gateway.permissionStatus();
    if (!invocation.result.ok || invocation.result.data == null) {
      return NotificationPermissionRefreshResult.failure(
        invocation.result.error?.message ??
            'Native notification operation failed.',
      );
    }
    return NotificationPermissionRefreshResult.success(invocation.result.data!);
  }

  Future<NotificationPermissionRequestResult> request(
    NotificationPermissionStatusDto status,
  ) async {
    final invocation = await _gateway.requestPermission(
      RequestNotificationPermissionRequestDto(
        requestNotificationPermission: !status.canPostNotifications,
        requestExactAlarmPermission: !status.canScheduleExactAlarms,
        source: NotificationPermissionRequestSource.appStartup,
      ),
    );
    if (!invocation.result.ok || invocation.result.data == null) {
      return NotificationPermissionRequestResult.failure(
        invocation.result.error?.message ??
            'Native notification operation failed.',
      );
    }
    final response = invocation.result.data!;
    return NotificationPermissionRequestResult.success(
      shouldOpenSettings: response.shouldOpenSettings,
      message: response.message,
    );
  }

  Future<void> openSettings(NotificationPermissionStatusDto? status) async {
    final target =
        status != null &&
            status.canPostNotifications &&
            !status.canScheduleExactAlarms
        ? NotificationSettingsTarget.exactAlarm
        : NotificationSettingsTarget.notification;
    await _gateway.openSettings(
      OpenNotificationSettingsRequestDto(settingsTarget: target),
    );
  }
}
