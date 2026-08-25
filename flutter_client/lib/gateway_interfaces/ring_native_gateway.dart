import '../native_contract/ring/ring_request_dtos.dart';
import '../native_contract/ring/ring_state_dtos.dart';
import '../native_contract/shared/native_invocation.dart';

sealed class RingStateEvent {
  const RingStateEvent();
}

final class RingStateChanged extends RingStateEvent {
  const RingStateChanged(this.event);
  final RingStateChangedEventDto event;
}

final class RingStateEventFailure extends RingStateEvent {
  const RingStateEventFailure(this.message);
  final String message;
}

abstract interface class RingNativeGateway {
  Stream<RingStateEvent> stateEvents();

  Future<NativeInvocation<RingStateSnapshotDto>> getState();

  Future<NativeInvocation<PickRingtoneResponseDto>> pickRingtone(
    PickRingtoneRequestDto request,
  );

  Future<NativeInvocation<RingStateSnapshotDto>> updateSettings(
    UpdateRingSettingsRequestDto request,
  );

  Future<NativeInvocation<RingStateSnapshotDto>> testRing(
    RingTestRequestDto request,
  );

  Future<NativeInvocation<RingStateSnapshotDto>> stopActive(
    ActiveRingItemsRequestDto request,
  );

  Future<NativeInvocation<RingSnoozeActiveResponseDto>> snoozeActive(
    ActiveRingItemsRequestDto request,
  );

  Future<NativeInvocation<RingStateSnapshotDto>> completeItem(
    CompleteRingItemRequestDto request,
  );
}
