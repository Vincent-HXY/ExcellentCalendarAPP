import 'package:flutter/services.dart';

import '../../boundary_adapters/dart_method_channel/native_method_channel_contract.dart';
import '../../boundary_adapters/dart_method_channel/native_method_channel_invoker.dart';
import '../../gateway_interfaces/refresh_token_secure_store_gateway.dart';
import '../../native_contract/auth/refresh_token_presence_response_dto.dart';
import '../../native_contract/auth/secure_refresh_token_record_response_dto.dart';
import '../../native_contract/auth/store_refresh_token_request_dto.dart';
import '../../native_contract/common/operation_response_dto.dart';
import '../../native_contract/shared/native_invocation.dart';
import '../../native_contract/shared/native_json_normalizer.dart';

/// RefreshTokenSecureStoreGateway over the auth.refresh_token.*
/// MethodChannel methods (Android Keystore implementation).
class MethodChannelRefreshTokenSecureStore
    implements RefreshTokenSecureStoreGateway {
  MethodChannelRefreshTokenSecureStore({
    MethodChannel channel = const MethodChannel(
      NativeMethodChannelNames.native,
    ),
  }) : _invoker = NativeMethodChannelInvoker(channel);

  final NativeMethodChannelInvoker _invoker;

  @override
  Future<NativeInvocation<OperationResponseDto>> store(
    StoreRefreshTokenRequestDto request,
  ) {
    return _invoker.invoke<OperationResponseDto>(
      method: NativeAuthMethods.refreshTokenStore,
      arguments: request.toJson(),
      parseData: (raw) =>
          OperationResponseDto.fromJson(NativeJsonNormalizer.normalizeMap(raw)),
    );
  }

  @override
  Future<NativeInvocation<SecureRefreshTokenRecordResponseDto>> read() {
    return _invoker.invoke<SecureRefreshTokenRecordResponseDto>(
      method: NativeAuthMethods.refreshTokenRead,
      arguments: const {},
      parseData: (raw) => SecureRefreshTokenRecordResponseDto.fromJson(
        NativeJsonNormalizer.normalizeMap(raw),
      ),
    );
  }

  @override
  Future<NativeInvocation<OperationResponseDto>> delete() {
    return _invoker.invoke<OperationResponseDto>(
      method: NativeAuthMethods.refreshTokenDelete,
      arguments: const {},
      parseData: (raw) =>
          OperationResponseDto.fromJson(NativeJsonNormalizer.normalizeMap(raw)),
    );
  }

  @override
  Future<NativeInvocation<RefreshTokenPresenceResponseDto>> exists() {
    return _invoker.invoke<RefreshTokenPresenceResponseDto>(
      method: NativeAuthMethods.refreshTokenExists,
      arguments: const {},
      parseData: (raw) => RefreshTokenPresenceResponseDto.fromJson(
        NativeJsonNormalizer.normalizeMap(raw),
      ),
    );
  }
}
