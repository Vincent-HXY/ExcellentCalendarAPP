import 'dart:async';

import 'package:flutter/services.dart';

import '../../gateway_interfaces/ring_native_gateway.dart';
import '../../native_contract/ring/ring_mapper.dart';
import '../../native_contract/ring/ring_request_dtos.dart';
import '../../native_contract/ring/ring_state_dtos.dart';
import '../../native_contract/shared/native_invocation.dart';
import '../../native_contract/shared/native_json_normalizer.dart';
import 'native_method_channel_contract.dart';
import 'native_method_channel_invoker.dart';

class MethodChannelRingAdapter implements RingNativeGateway {
  MethodChannelRingAdapter({
    MethodChannel channel = const MethodChannel(
      NativeMethodChannelNames.native,
    ),
    EventChannel stateChannel = const EventChannel(
      NativeMethodChannelNames.ringState,
    ),
    Stream<Object?>? stateEventStream,
  }) : _invoker = NativeMethodChannelInvoker(channel),
       _stateEventStream =
           stateEventStream ?? stateChannel.receiveBroadcastStream();

  final NativeMethodChannelInvoker _invoker;
  final Stream<Object?> _stateEventStream;

  @override
  Stream<RingStateEvent> stateEvents() {
    return _stateEventStream.transform(
      StreamTransformer<Object?, RingStateEvent>.fromHandlers(
        handleData: (raw, sink) {
          try {
            sink.add(
              RingStateChanged(
                RingMapper.stateChangedEvent(
                  NativeJsonNormalizer.normalizeMap(raw),
                ),
              ),
            );
          } on FormatException catch (error) {
            sink.add(RingStateEventFailure(error.message));
          }
        },
        handleError: (Object error, StackTrace stackTrace, sink) {
          sink.add(RingStateEventFailure(error.toString()));
        },
      ),
    );
  }

  @override
  Future<NativeInvocation<RingStateSnapshotDto>> getState() {
    return _state(NativeRingMethods.getState, const {});
  }

  @override
  Future<NativeInvocation<PickRingtoneResponseDto>> pickRingtone(
    PickRingtoneRequestDto request,
  ) {
    return _invoker.invoke<PickRingtoneResponseDto>(
      method: NativeRingMethods.pickRingtone,
      arguments: request.toJson(),
      parseData: RingMapper.pickRingtoneResponse,
    );
  }

  @override
  Future<NativeInvocation<RingStateSnapshotDto>> updateSettings(
    UpdateRingSettingsRequestDto request,
  ) {
    return _state(NativeRingMethods.updateSettings, request.toJson());
  }

  @override
  Future<NativeInvocation<RingStateSnapshotDto>> testRing(
    RingTestRequestDto request,
  ) {
    return _state(NativeRingMethods.test, request.toJson());
  }

  @override
  Future<NativeInvocation<RingStateSnapshotDto>> stopActive(
    ActiveRingItemsRequestDto request,
  ) {
    return _state(NativeRingMethods.stopActive, request.toJson());
  }

  @override
  Future<NativeInvocation<RingSnoozeActiveResponseDto>> snoozeActive(
    ActiveRingItemsRequestDto request,
  ) {
    return _invoker.invoke<RingSnoozeActiveResponseDto>(
      method: NativeRingMethods.snoozeActive,
      arguments: request.toJson(),
      parseData: (raw) =>
          RingMapper.snoozeActiveResponse(raw, request.deliveryIds),
    );
  }

  @override
  Future<NativeInvocation<RingStateSnapshotDto>> completeItem(
    CompleteRingItemRequestDto request,
  ) {
    return _state(NativeRingMethods.completeItem, request.toJson());
  }

  Future<NativeInvocation<RingStateSnapshotDto>> _state(
    String method,
    Map<String, dynamic> arguments,
  ) {
    return _invoker.invoke<RingStateSnapshotDto>(
      method: method,
      arguments: arguments,
      parseData: RingMapper.stateSnapshot,
    );
  }
}
