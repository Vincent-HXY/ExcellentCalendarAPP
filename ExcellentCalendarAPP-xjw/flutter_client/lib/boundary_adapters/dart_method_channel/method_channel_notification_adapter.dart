import 'dart:async';

import 'package:flutter/services.dart';

import '../../gateway_interfaces/notification_native_gateway.dart';
import '../../native_contract/common/operation_response_dto.dart';
import '../../native_contract/notification/notification_initialize_response_dto.dart';
import '../../native_contract/notification/notification_mapper.dart';
import '../../native_contract/notification/notification_permission_status_dto.dart';
import '../../native_contract/notification/notification_tap_payload_dto.dart';
import '../../native_contract/notification/open_notification_settings_request_dto.dart';
import '../../native_contract/notification/request_notification_permission_dto.dart';
import '../../native_contract/shared/native_invocation.dart';
import '../../native_contract/shared/native_json_normalizer.dart';
import 'native_method_channel_contract.dart';
import 'native_method_channel_invoker.dart';

class MethodChannelNotificationAdapter implements NotificationNativeGateway {
  MethodChannelNotificationAdapter({
    MethodChannel channel = const MethodChannel(
      NativeMethodChannelNames.native,
    ),
    EventChannel openedChannel = const EventChannel(
      NativeMethodChannelNames.notificationOpened,
    ),
    Stream<Object?>? openedEventStream,
  }) : _invoker = NativeMethodChannelInvoker(channel),
       _openedEventStream =
           openedEventStream ?? openedChannel.receiveBroadcastStream();

  final NativeMethodChannelInvoker _invoker;
  final Stream<Object?> _openedEventStream;

  @override
  Stream<NotificationOpenedEvent> openedEvents() {
    return _openedEventStream.transform(
      StreamTransformer<Object?, NotificationOpenedEvent>.fromHandlers(
        handleData: (raw, sink) {
          try {
            final json = NativeJsonNormalizer.normalizeMap(raw);
            sink.add(
              NotificationOpenedPayload(
                NotificationTapPayloadDto.fromJson(json),
              ),
            );
          } on FormatException catch (error) {
            sink.add(NotificationOpenedFailure(error.message));
          }
        },
        handleError: (Object error, StackTrace stackTrace, sink) {
          sink.add(NotificationOpenedFailure(error.toString()));
        },
      ),
    );
  }

  @override
  Future<NativeInvocation<NotificationInitializeResponseDto>> initialize() {
    return _invoker.invoke<NotificationInitializeResponseDto>(
      method: NativeNotificationMethods.initialize,
      arguments: const {},
      parseData: NotificationMapper.initializeResponse,
    );
  }

  @override
  Future<NativeInvocation<NotificationPermissionStatusDto>> permissionStatus() {
    return _invoker.invoke<NotificationPermissionStatusDto>(
      method: NativeNotificationMethods.permissionStatus,
      arguments: const {},
      parseData: NotificationMapper.permissionStatus,
    );
  }

  @override
  Future<NativeInvocation<RequestNotificationPermissionResponseDto>>
  requestPermission(RequestNotificationPermissionRequestDto request) {
    return _invoker.invoke<RequestNotificationPermissionResponseDto>(
      method: NativeNotificationMethods.requestPermission,
      arguments: request.toJson(),
      parseData: NotificationMapper.permissionRequest,
    );
  }

  @override
  Future<NativeInvocation<OperationResponseDto>> openSettings(
    OpenNotificationSettingsRequestDto request,
  ) {
    return _invoker.invoke<OperationResponseDto>(
      method: NativeNotificationMethods.openSettings,
      arguments: request.toJson(),
      parseData: NotificationMapper.operationResponse,
    );
  }

  @override
  Future<NativeInvocation<NotificationTapPayloadResponseDto>>
  getInitialTapPayload() {
    return _invoker.invoke<NotificationTapPayloadResponseDto>(
      method: NativeNotificationMethods.getInitialTapPayload,
      arguments: const {},
      parseData: NotificationMapper.initialTapPayload,
    );
  }
}
