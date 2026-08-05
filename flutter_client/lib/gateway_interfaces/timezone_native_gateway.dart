import '../native_contract/runtime/device_timezone_response_dto.dart';
import '../native_contract/runtime/localize_instants_dto.dart';
import '../native_contract/runtime/resolve_local_datetime_dto.dart';
import '../native_contract/shared/native_invocation.dart';

abstract interface class TimezoneNativeGateway {
  Future<NativeInvocation<DeviceTimezoneResponseDto>> getDeviceTimezone();

  Future<NativeInvocation<ResolveLocalDateTimeResponseDto>>
  resolveLocalDateTime(ResolveLocalDateTimeRequestDto request);

  Future<NativeInvocation<LocalizeInstantsResponseDto>> localizeInstants(
    LocalizeInstantsRequestDto request,
  );
}
