import 'package:flutter/services.dart';

import '../../gateway_interfaces/appearance_preferences_gateway.dart';
import '../../native_contract/appearance/appearance_contract.dart';
import '../../native_contract/shared/native_invocation.dart';
import 'native_method_channel_contract.dart';
import 'native_method_channel_invoker.dart';

class MethodChannelAppearanceAdapter implements AppearancePreferencesGateway {
  MethodChannelAppearanceAdapter({MethodChannel? channel})
    : _invoker = NativeMethodChannelInvoker(
        channel ?? const MethodChannel(NativeMethodChannelNames.native),
      );
  final NativeMethodChannelInvoker _invoker;

  @override
  Future<LocalAppearanceResponseDto> getLocal() =>
      _call(NativeAppearanceMethods.getLocal, const {});

  @override
  Future<LocalAppearanceResponseDto> updateLocal(
    UpdateLocalAppearanceRequestDto request,
  ) => _call(NativeAppearanceMethods.updateLocal, request.toJson());

  Future<LocalAppearanceResponseDto> _call(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    final invocation = await _invoker.invoke<LocalAppearanceResponseDto>(
      method: method,
      arguments: arguments,
      parseData: (raw) => LocalAppearanceResponseDto.fromJson(
        raw is Map<String, dynamic>
            ? raw
            : throw const FormatException(
                'LocalAppearanceResponse must be object.',
              ),
      ),
    );
    return _unwrap(invocation);
  }

  LocalAppearanceResponseDto _unwrap(
    NativeInvocation<LocalAppearanceResponseDto> invocation,
  ) {
    final data = invocation.result.data;
    if (invocation.result.ok && data != null) return data;
    final error = invocation.result.error;
    throw AppearanceGatewayFailure(
      code: error?.code ?? 'NATIVE_INTERNAL_ERROR',
      message: error?.message ?? 'Appearance native invocation failed.',
      retryable: error?.retryable ?? false,
    );
  }
}
