import '../native_contract/common/operation_response_dto.dart';
import '../native_contract/notification/notification_initialize_response_dto.dart';
import '../native_contract/notification/notification_permission_status_dto.dart';
import '../native_contract/notification/notification_tap_payload_dto.dart';
import '../native_contract/notification/open_notification_settings_request_dto.dart';
import '../native_contract/notification/request_notification_permission_dto.dart';
import '../native_contract/shared/native_invocation.dart';

sealed class NotificationOpenedEvent {
  const NotificationOpenedEvent();
}

final class NotificationOpenedPayload extends NotificationOpenedEvent {
  const NotificationOpenedPayload(this.payload);
  final NotificationTapPayloadDto payload;
}

final class NotificationOpenedFailure extends NotificationOpenedEvent {
  const NotificationOpenedFailure(this.message);
  final String message;
}

abstract interface class NotificationNativeGateway {
  Stream<NotificationOpenedEvent> openedEvents();

  Future<NativeInvocation<NotificationInitializeResponseDto>> initialize();

  Future<NativeInvocation<NotificationPermissionStatusDto>> permissionStatus();

  Future<NativeInvocation<RequestNotificationPermissionResponseDto>>
  requestPermission(RequestNotificationPermissionRequestDto request);

  Future<NativeInvocation<OperationResponseDto>> openSettings(
    OpenNotificationSettingsRequestDto request,
  );

  Future<NativeInvocation<NotificationTapPayloadResponseDto>>
  getInitialTapPayload();
}
