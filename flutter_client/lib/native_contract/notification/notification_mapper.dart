import '../common/operation_response_dto.dart';
import 'notification_initialize_response_dto.dart';
import 'notification_permission_status_dto.dart';
import 'notification_tap_payload_dto.dart';
import 'request_notification_permission_dto.dart';

class NotificationMapper {
  const NotificationMapper._();

  static NotificationInitializeResponseDto initializeResponse(Object? raw) =>
      NotificationInitializeResponseDto.fromJson(_object(raw));

  static NotificationPermissionStatusDto permissionStatus(Object? raw) =>
      NotificationPermissionStatusDto.fromJson(_object(raw));

  static RequestNotificationPermissionResponseDto permissionRequest(
    Object? raw,
  ) => RequestNotificationPermissionResponseDto.fromJson(_object(raw));

  static OperationResponseDto operationResponse(Object? raw) =>
      OperationResponseDto.fromJson(_object(raw));

  static NotificationTapPayloadResponseDto initialTapPayload(Object? raw) =>
      NotificationTapPayloadResponseDto.fromJson(_object(raw));

  static Map<String, dynamic> _object(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    throw const FormatException('Notification response data must be object.');
  }
}
