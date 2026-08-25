import '../native_contract/auth/authentication_response_dto.dart';
import '../native_contract/auth/change_password_request_dto.dart';
import '../native_contract/auth/confirm_email_change_request_dto.dart';
import '../native_contract/auth/confirm_password_reset_request_dto.dart';
import '../native_contract/auth/email_challenge_response_dto.dart';
import '../native_contract/auth/login_request_dto.dart';
import '../native_contract/auth/logout_request_dto.dart';
import '../native_contract/auth/password_reset_dispatch_response_dto.dart';
import '../native_contract/auth/password_reset_request_dto.dart';
import '../native_contract/auth/refresh_session_request_dto.dart';
import '../native_contract/auth/registration_pending_response_dto.dart';
import '../native_contract/auth/registration_request_dto.dart';
import '../native_contract/auth/request_email_change_request_dto.dart';
import '../native_contract/auth/resend_registration_request_dto.dart';
import '../native_contract/auth/token_pair_response_dto.dart';
import '../native_contract/auth/verify_registration_request_dto.dart';

/// Typed business gateway for all Backend authentication endpoints.
///
/// Implementations talk to the Backend directly over HTTPS. Failures are
/// thrown as BackendApiException / BackendTransportException /
/// BackendContractException / SessionEndedException; no platform details.
abstract interface class AuthGateway {
  Future<RegistrationPendingResponseDto> register(
    RegistrationRequestDto request, {
    required String idempotencyKey,
  });

  Future<AuthenticationResponseDto> verifyRegistration(
    VerifyRegistrationRequestDto request,
  );

  Future<EmailChallengeResponseDto> resendRegistration(
    ResendRegistrationRequestDto request, {
    required String idempotencyKey,
  });

  Future<AuthenticationResponseDto> login(LoginRequestDto request);

  Future<TokenPairResponseDto> refreshSession(RefreshSessionRequestDto request);

  Future<void> logout(LogoutRequestDto request);

  Future<void> logoutAll();

  Future<PasswordResetDispatchResponseDto> requestPasswordReset(
    PasswordResetRequestDto request, {
    required String idempotencyKey,
  });

  Future<void> confirmPasswordReset(ConfirmPasswordResetRequestDto request);

  Future<AuthenticationResponseDto> changePassword(
    ChangePasswordRequestDto request,
  );

  Future<EmailChallengeResponseDto> requestEmailChange(
    RequestEmailChangeRequestDto request, {
    required String idempotencyKey,
  });

  Future<AuthenticationResponseDto> confirmEmailChange(
    ConfirmEmailChangeRequestDto request,
  );
}
