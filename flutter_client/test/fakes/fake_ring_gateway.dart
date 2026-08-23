import 'dart:async';

import 'package:excellent_calendar/gateway_interfaces/ring_native_gateway.dart';
import 'package:excellent_calendar/native_contract/ring/ring_request_dtos.dart';
import 'package:excellent_calendar/native_contract/ring/ring_state_dtos.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';

typedef GetRingStateHandler =
    Future<NativeInvocation<RingStateSnapshotDto>> Function();
typedef PickRingtoneHandler =
    Future<NativeInvocation<PickRingtoneResponseDto>> Function(
      PickRingtoneRequestDto request,
    );
typedef RingStateRequestHandler<T> =
    Future<NativeInvocation<T>> Function(Object request);

class FakeRingGateway implements RingNativeGateway {
  FakeRingGateway({
    required this.onGetState,
    this.onPickRingtone,
    this.onUpdateSettings,
    this.onTestRing,
    this.onStopActive,
    this.onSnoozeActive,
    this.onCompleteItem,
    StreamController<RingStateEvent>? eventController,
    this.callLog,
  }) : eventController =
           eventController ??
           StreamController<RingStateEvent>.broadcast(sync: true);

  final GetRingStateHandler onGetState;
  final PickRingtoneHandler? onPickRingtone;
  final RingStateRequestHandler<RingStateSnapshotDto>? onUpdateSettings;
  final RingStateRequestHandler<RingStateSnapshotDto>? onTestRing;
  final RingStateRequestHandler<RingStateSnapshotDto>? onStopActive;
  final RingStateRequestHandler<RingSnoozeActiveResponseDto>? onSnoozeActive;
  final RingStateRequestHandler<RingStateSnapshotDto>? onCompleteItem;
  final StreamController<RingStateEvent> eventController;
  final List<String>? callLog;

  @override
  Stream<RingStateEvent> stateEvents() {
    callLog?.add('state_events');
    return eventController.stream;
  }

  @override
  Future<NativeInvocation<RingStateSnapshotDto>> getState() {
    callLog?.add('get_state');
    return onGetState();
  }

  @override
  Future<NativeInvocation<PickRingtoneResponseDto>> pickRingtone(
    PickRingtoneRequestDto request,
  ) {
    callLog?.add('pick_ringtone');
    final handler = onPickRingtone;
    if (handler == null) throw StateError('pickRingtone is not configured.');
    return handler(request);
  }

  @override
  Future<NativeInvocation<RingStateSnapshotDto>> updateSettings(
    UpdateRingSettingsRequestDto request,
  ) {
    callLog?.add('update_settings');
    return _required(onUpdateSettings, request, 'updateSettings');
  }

  @override
  Future<NativeInvocation<RingStateSnapshotDto>> testRing(
    RingTestRequestDto request,
  ) {
    callLog?.add('test');
    return _required(onTestRing, request, 'testRing');
  }

  @override
  Future<NativeInvocation<RingStateSnapshotDto>> stopActive(
    ActiveRingItemsRequestDto request,
  ) {
    callLog?.add('stop_active');
    return _required(onStopActive, request, 'stopActive');
  }

  @override
  Future<NativeInvocation<RingSnoozeActiveResponseDto>> snoozeActive(
    ActiveRingItemsRequestDto request,
  ) {
    callLog?.add('snooze_active');
    return _required(onSnoozeActive, request, 'snoozeActive');
  }

  @override
  Future<NativeInvocation<RingStateSnapshotDto>> completeItem(
    CompleteRingItemRequestDto request,
  ) {
    callLog?.add('complete_item');
    return _required(onCompleteItem, request, 'completeItem');
  }

  Future<NativeInvocation<T>> _required<T>(
    RingStateRequestHandler<T>? handler,
    Object request,
    String name,
  ) {
    if (handler == null) throw StateError('$name is not configured.');
    return handler(request);
  }
}
