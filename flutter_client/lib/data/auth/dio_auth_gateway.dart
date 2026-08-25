import '../../boundary_adapters/backend_api/backend_api_endpoints.dart';
import '../../boundary_adapters/backend_api/dio_backend_api_client.dart';
import '../../gateway_interfaces/auth_gateway.dart';
import '../../native_contract/auth/authentication_response_dto.dart';
import '../../native_contract/auth/change_password_request_dto.dart';
import '../../native_contract/auth/confirm_email_change_request_dto.dart';
import '../../native_contract/auth/confirm_password_reset_request_dto.dart';
import '../../native_contract/auth/email_challenge_response_dto.dart';
import '../../native_contract/auth/login_request_dto.dart';
import '../../native_contract/auth/logout_request_dto.dart';
import '../../native_contract/auth/password_reset_dispatch_response_dto.dart';
import '../../native_contract/auth/password_reset_request_dto.dart';
import '../../native_contract/auth/refresh_session_request_dto.dart';
import '../../native_contract/auth/registration_pending_response_dto.dart';
import '../../native_contract/auth/registration_request_dto.dart';
import '../../native_contract/auth/request_email_change_request_dto.dart';
import '../../native_contract/auth/resend_registration_request_dto.dart';
import '../../native_contract/auth/token_pair_response_dto.dart';
import '../../native_contract/auth/verify_registration_request_dto.dart';
import '../../native_contract/common/operation_response_dto.dart';
import '../../native_contract/shared/native_json_normalizer.dart';

/// AuthGateway implementation over the unified dio API client.
class DioAuthGateway implements AuthGateway {
  const DioAuthGateway(this._client);

  final DioBackendApiClient _client;

  @override
  Future<RegistrationPendingResponseDto> register(
    RegistrationRequestDto request, {
    required String idempotencyKey,
  }) {
    return _client.send<RegistrationPendingResponseDto>(
      endpoint: BackendApiEndpoints.register,
      data: request.toJson(),
      idempotencyKey: idempotencyKey,
      parseData: (raw) => RegistrationPendingResponseDto.fromJson(
        NativeJsonNormalizer.normalizeMap(raw),
      ),
    );
  }

  @override
  Future<AuthenticationResponseDto> verifyRegistration(
    VerifyRegistrationRequestDto request,
  ) {
    return _client.send<AuthenticationResponseDto>(
      endpoint: BackendApiEndpoints.registrationVerify,
      data: request.toJson(),
      parseData: (raw) => AuthenticationResponseDto.fromJson(
        NativeJsonNormalizer.normalizeMap(raw),
      ),
    );
  }

  @override
  Future<EmailChallengeResponseDto> resendRegistration(
    ResendRegistrationRequestDto request, {
    required String idempotencyKey,
  }) {
    return _client.send<EmailChallengeResponseDto>(
      endpoint: BackendApiEndpoints.registrationResend,
      data: request.toJson(),
      idempotencyKey: idempotencyKey,
      parseData: (raw) => EmailChallengeResponseDto.fromJson(
        NativeJsonNormalizer.normalizeMap(raw),
      ),
    );
  }

  @override
  Future<AuthenticationResponseDto> login(LoginRequestDto request) {
    return _client.send<AuthenticationResponseDto>(
      endpoint: BackendApiEndpoints.login,
      data: request.toJson(),
      parseData: (raw) => AuthenticationResponseDto.fromJson(
        NativeJsonNormalizer.normalizeMap(raw),
      ),
    );
  }

  @override
  Future<TokenPairResponseDto> refreshSession(
    RefreshSessionRequestDto request,
  ) {
    return _client.send<TokenPairResponseDto>(
      endpoint: BackendApiEndpoints.tokenRefresh,
      data: request.toJson(),
      parseData: (raw) =>
          TokenPairResponseDto.fromJson(NativeJsonNormalizer.normalizeMap(raw)),
    );
  }

  @override
  Future<void> logout(LogoutRequestDto request) async {
    await _client.send<OperationResponseDto>(
      endpoint: BackendApiEndpoints.logout,
      data: request.toJson(),
      parseData: (raw) =>
          OperationResponseDto.fromJson(NativeJsonNormalizer.normalizeMap(raw)),
    );
  }

  @override
  Future<void> logoutAll() async {
    await _client.send<OperationResponseDto>(
      endpoint: BackendApiEndpoints.logoutAll,
      data: const <String, dynamic>{},
      parseData: (raw) =>
          OperationResponseDto.fromJson(NativeJsonNormalizer.normalizeMap(raw)),
    );
  }

  @override
  Future<PasswordResetDispatchResponseDto> requestPasswordReset(
    PasswordResetRequestDto request, {
    required String idempotencyKey,
  }) {
    return _client.send<PasswordResetDispatchResponseDto>(
      endpoint: BackendApiEndpoints.passwordResetRequest,
      data: request.toJson(),
      idempotencyKey: idempotencyKey,
      parseData: (raw) => PasswordResetDispatchResponseDto.fromJson(
        NativeJsonNormalizer.normalizeMap(raw),
      ),
    );
  }

  @override
  Future<void> confirmPasswordReset(
    ConfirmPasswordResetRequestDto request,
  ) async {
    await _client.send<OperationResponseDto>(
      endpoint: BackendApiEndpoints.passwordResetConfirm,
      data: request.toJson(),
      parseData: (raw) =>
          OperationResponseDto.fromJson(NativeJsonNormalizer.normalizeMap(raw)),
    );
  }

  @override
  Future<AuthenticationResponseDto> changePassword(
    ChangePasswordRequestDto request,
  ) {
    return _client.send<AuthenticationResponseDto>(
      endpoint: BackendApiEndpoints.passwordChange,
      data: request.toJson(),
      parseData: (raw) => AuthenticationResponseDto.fromJson(
        NativeJsonNormalizer.normalizeMap(raw),
      ),
    );
  }

  @override
  Future<EmailChallengeResponseDto> requestEmailChange(
    RequestEmailChangeRequestDto request, {
    required String idempotencyKey,
  }) {
    return _client.send<EmailChallengeResponseDto>(
      endpoint: BackendApiEndpoints.emailChangeRequest,
      data: request.toJson(),
      idempotencyKey: idempotencyKey,
      parseData: (raw) => EmailChallengeResponseDto.fromJson(
        NativeJsonNormalizer.normalizeMap(raw),
      ),
    );
  }

  @override
  Future<AuthenticationResponseDto> confirmEmailChange(
    ConfirmEmailChangeRequestDto request,
  ) {
    return _client.send<AuthenticationResponseDto>(
      endpoint: BackendApiEndpoints.emailChangeConfirm,
      data: request.toJson(),
      parseData: (raw) => AuthenticationResponseDto.fromJson(
        NativeJsonNormalizer.normalizeMap(raw),
      ),
    );
  }
}
