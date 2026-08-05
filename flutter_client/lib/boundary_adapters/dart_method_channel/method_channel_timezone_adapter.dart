import 'package:flutter/services.dart';

import '../../gateway_interfaces/timezone_native_gateway.dart';
import '../../native_contract/runtime/device_timezone_response_dto.dart';
import '../../native_contract/runtime/localize_instants_dto.dart';
import '../../native_contract/runtime/resolve_local_datetime_dto.dart';
import '../../native_contract/shared/contract_value.dart';
import '../../native_contract/shared/native_invocation.dart';
import '../../native_contract/shared/native_json_normalizer.dart';
import 'native_method_channel_contract.dart';
import 'native_method_channel_invoker.dart';

class MethodChannelTimezoneAdapter implements TimezoneNativeGateway {
  MethodChannelTimezoneAdapter({
    MethodChannel channel = const MethodChannel(
      NativeMethodChannelNames.native,
    ),
  }) : _invoker = NativeMethodChannelInvoker(channel);

  final NativeMethodChannelInvoker _invoker;

  @override
  Future<NativeInvocation<DeviceTimezoneResponseDto>> getDeviceTimezone() {
    return _invoker.invoke<DeviceTimezoneResponseDto>(
      method: NativeRuntimeMethods.deviceTimezone,
      arguments: const {},
      parseData: (raw) => DeviceTimezoneResponseDto.fromJson(
        NativeJsonNormalizer.normalizeMap(raw),
      ),
    );
  }

  @override
  Future<NativeInvocation<ResolveLocalDateTimeResponseDto>>
  resolveLocalDateTime(ResolveLocalDateTimeRequestDto request) {
    return _invoker.invoke<ResolveLocalDateTimeResponseDto>(
      method: NativeRuntimeMethods.resolveLocalDateTime,
      arguments: request.toJson(),
      parseData: (raw) {
        final response = ResolveLocalDateTimeResponseDto.fromJson(
          NativeJsonNormalizer.normalizeMap(raw),
        );
        if (response.requestedLocalDateTime != request.localDateTime ||
            response.timezone != request.timezone) {
          throw const FormatException(
            'ResolveLocalDateTimeResponse does not match its request.',
          );
        }
        return response;
      },
    );
  }

  @override
  Future<NativeInvocation<LocalizeInstantsResponseDto>> localizeInstants(
    LocalizeInstantsRequestDto request,
  ) {
    final expectedInstants = request.encodedInstants;
    return _invoker.invoke<LocalizeInstantsResponseDto>(
      method: NativeRuntimeMethods.localizeInstants,
      arguments: request.toJson(),
      parseData: (raw) {
        final response = LocalizeInstantsResponseDto.fromJson(
          NativeJsonNormalizer.normalizeMap(raw),
        );
        if (response.timezone != request.timezone ||
            response.items.length != expectedInstants.length) {
          throw const FormatException(
            'LocalizeInstantsResponse does not match its request.',
          );
        }
        for (var index = 0; index < response.items.length; index++) {
          final actual = ContractValue.formatUtcSecond(
            response.items[index].instant,
            field: 'LocalizedInstant.instant',
          );
          if (actual != expectedInstants[index]) {
            throw const FormatException(
              'LocalizeInstantsResponse must preserve input order.',
            );
          }
        }
        return response;
      },
    );
  }
}
