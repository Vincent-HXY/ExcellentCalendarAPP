import 'dart:async';

import 'package:excellent_calendar/gateway_interfaces/notification_native_gateway.dart';
import 'package:excellent_calendar/native_contract/common/operation_response_dto.dart';
import 'package:excellent_calendar/native_contract/notification/notification_initialize_response_dto.dart';
import 'package:excellent_calendar/native_contract/notification/notification_permission_status_dto.dart';
import 'package:excellent_calendar/native_contract/notification/notification_tap_payload_dto.dart';
import 'package:excellent_calendar/native_contract/notification/open_notification_settings_request_dto.dart';
import 'package:excellent_calendar/native_contract/notification/request_notification_permission_dto.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';

class FakeNotificationGateway implements NotificationNativeGateway {
  FakeNotificationGateway({
    required this.initializeInvocation,
    required this.permissionStatusInvocation,
    required this.permissionRequestInvocation,
    required this.openSettingsInvocation,
    required this.initialPayloadInvocation,
    StreamController<NotificationOpenedEvent>? openedController,
    this.callLog,
  }) : openedController =
           openedController ?? StreamController<NotificationOpenedEvent>();

  final NativeInvocation<NotificationInitializeResponseDto>
  initializeInvocation;
  NativeInvocation<NotificationPermissionStatusDto> permissionStatusInvocation;
  final NativeInvocation<RequestNotificationPermissionResponseDto>
  permissionRequestInvocation;
  final NativeInvocation<OperationResponseDto> openSettingsInvocation;
  final NativeInvocation<NotificationTapPayloadResponseDto>
  initialPayloadInvocation;
  final StreamController<NotificationOpenedEvent> openedController;
  final List<String>? callLog;

  @override
  Stream<NotificationOpenedEvent> openedEvents() {
    callLog?.add('opened.listen');
    return openedController.stream;
  }

  @override
  Future<NativeInvocation<NotificationInitializeResponseDto>>
  initialize() async {
    callLog?.add('initialize');
    return initializeInvocation;
  }

  @override
  Future<NativeInvocation<NotificationPermissionStatusDto>>
  permissionStatus() async {
    callLog?.add('permission_status');
    return permissionStatusInvocation;
  }

  @override
  Future<NativeInvocation<RequestNotificationPermissionResponseDto>>
  requestPermission(RequestNotificationPermissionRequestDto request) async {
    callLog?.add('request_permission');
    return permissionRequestInvocation;
  }

  @override
  Future<NativeInvocation<OperationResponseDto>> openSettings(
    OpenNotificationSettingsRequestDto request,
  ) async {
    callLog?.add('open_settings');
    return openSettingsInvocation;
  }

  @override
  Future<NativeInvocation<NotificationTapPayloadResponseDto>>
  getInitialTapPayload() async {
    callLog?.add('initial_payload');
    return initialPayloadInvocation;
  }
}
