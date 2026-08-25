import '../shared/native_json_normalizer.dart';
import 'ring_state_dtos.dart';

class RingMapper {
  const RingMapper._();

  static RingStateSnapshotDto stateSnapshot(Object? raw) =>
      RingStateSnapshotDto.fromJson(NativeJsonNormalizer.normalizeMap(raw));

  static RingStateChangedEventDto stateChangedEvent(Object? raw) =>
      RingStateChangedEventDto.fromJson(NativeJsonNormalizer.normalizeMap(raw));

  static PickRingtoneResponseDto pickRingtoneResponse(Object? raw) =>
      PickRingtoneResponseDto.fromJson(NativeJsonNormalizer.normalizeMap(raw));

  static RingSnoozeActiveResponseDto snoozeActiveResponse(
    Object? raw,
    List<String> requestedDeliveryIds,
  ) => RingSnoozeActiveResponseDto.fromJson(
    NativeJsonNormalizer.normalizeMap(raw),
    requestedDeliveryIds: requestedDeliveryIds,
  );
}
