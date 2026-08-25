import '../native_contract/auth/refresh_token_presence_response_dto.dart';
import '../native_contract/auth/secure_refresh_token_record_response_dto.dart';
import '../native_contract/auth/store_refresh_token_request_dto.dart';
import '../native_contract/common/operation_response_dto.dart';
import '../native_contract/shared/native_invocation.dart';

/// Android Keystore-backed Refresh Token storage (auth.refresh_token.*).
///
/// The Refresh Token only passes through this gateway on its way between the
/// Backend and Android secure storage; implementations must never log it.
abstract interface class RefreshTokenSecureStoreGateway {
  Future<NativeInvocation<OperationResponseDto>> store(
    StoreRefreshTokenRequestDto request,
  );

  Future<NativeInvocation<SecureRefreshTokenRecordResponseDto>> read();

  Future<NativeInvocation<OperationResponseDto>> delete();

  Future<NativeInvocation<RefreshTokenPresenceResponseDto>> exists();
}
