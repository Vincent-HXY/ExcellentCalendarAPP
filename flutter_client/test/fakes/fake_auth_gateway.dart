import 'package:excellent_calendar/gateway_interfaces/auth_gateway.dart';
import 'package:excellent_calendar/native_contract/auth/authentication_response_dto.dart';
import 'package:excellent_calendar/native_contract/auth/change_password_request_dto.dart';
import 'package:excellent_calendar/native_contract/auth/confirm_email_change_request_dto.dart';
import 'package:excellent_calendar/native_contract/auth/confirm_password_reset_request_dto.dart';
import 'package:excellent_calendar/native_contract/auth/email_challenge_response_dto.dart';
import 'package:excellent_calendar/native_contract/auth/login_request_dto.dart';
import 'package:excellent_calendar/native_contract/auth/logout_request_dto.dart';
import 'package:excellent_calendar/native_contract/auth/password_reset_dispatch_response_dto.dart';
import 'package:excellent_calendar/native_contract/auth/password_reset_request_dto.dart';
import 'package:excellent_calendar/native_contract/auth/refresh_session_request_dto.dart';
import 'package:excellent_calendar/native_contract/auth/registration_pending_response_dto.dart';
import 'package:excellent_calendar/native_contract/auth/registration_request_dto.dart';
import 'package:excellent_calendar/native_contract/auth/request_email_change_request_dto.dart';
import 'package:excellent_calendar/native_contract/auth/resend_registration_request_dto.dart';
import 'package:excellent_calendar/native_contract/auth/token_pair_response_dto.dart';
import 'package:excellent_calendar/native_contract/auth/verify_registration_request_dto.dart';

/// Programmable in-memory AuthGateway for tests.
class FakeAuthGateway implements AuthGateway {
  Object? Function(RegistrationRequestDto, {required String idempotencyKey})?
  onRegister;
  Object? Function(VerifyRegistrationRequestDto)? onVerifyRegistration;
  Object? Function(
    ResendRegistrationRequestDto, {
    required String idempotencyKey,
  })?
  onResendRegistration;
  Object? Function(LoginRequestDto)? onLogin;
  Object? Function(RefreshSessionRequestDto)? onRefreshSession;
  Object? Function(LogoutRequestDto)? onLogout;
  Object? Function()? onLogoutAll;
  Object? Function(PasswordResetRequestDto, {required String idempotencyKey})?
  onPasswordResetRequest;
  Object? Function(ConfirmPasswordResetRequestDto)? onPasswordResetConfirm;
  Object? Function(ChangePasswordRequestDto)? onChangePassword;
  Object? Function(
    RequestEmailChangeRequestDto, {
    required String idempotencyKey,
  })?
  onEmailChangeRequest;
  Object? Function(ConfirmEmailChangeRequestDto)? onEmailChangeConfirm;

  int refreshCalls = 0;
  int logoutCalls = 0;
  int logoutAllCalls = 0;

  Future<Object?> _invoke(Object? Function() call) async {
    final result = call();
    if (result is Future) {
      return await result;
    }
    return result;
  }

  Never _throwResult(Object? result) {
    if (result is Exception) {
      throw result;
    }
    throw StateError('FakeAuthGateway result must be set.');
  }

  @override
  Future<RegistrationPendingResponseDto> register(
    RegistrationRequestDto request, {
    required String idempotencyKey,
  }) async {
    final result = await _invoke(
      () => onRegister?.call(request, idempotencyKey: idempotencyKey),
    );
    if (result is RegistrationPendingResponseDto) return result;
    _throwResult(result);
  }

  @override
  Future<AuthenticationResponseDto> verifyRegistration(
    VerifyRegistrationRequestDto request,
  ) async {
    final result = await _invoke(() => onVerifyRegistration?.call(request));
    if (result is AuthenticationResponseDto) return result;
    _throwResult(result);
  }

  @override
  Future<EmailChallengeResponseDto> resendRegistration(
    ResendRegistrationRequestDto request, {
    required String idempotencyKey,
  }) async {
    final result = await _invoke(
      () => onResendRegistration?.call(request, idempotencyKey: idempotencyKey),
    );
    if (result is EmailChallengeResponseDto) return result;
    _throwResult(result);
  }

  @override
  Future<AuthenticationResponseDto> login(LoginRequestDto request) async {
    final result = await _invoke(() => onLogin?.call(request));
    if (result is AuthenticationResponseDto) return result;
    _throwResult(result);
  }

  @override
  Future<TokenPairResponseDto> refreshSession(
    RefreshSessionRequestDto request,
  ) async {
    refreshCalls += 1;
    final result = await _invoke(() => onRefreshSession?.call(request));
    if (result is TokenPairResponseDto) return result;
    _throwResult(result);
  }

  @override
  Future<void> logout(LogoutRequestDto request) async {
    logoutCalls += 1;
    final result = await _invoke(() => onLogout?.call(request));
    if (result == null) return;
    _throwResult(result);
  }

  @override
  Future<void> logoutAll() async {
    logoutAllCalls += 1;
    final result = await _invoke(() => onLogoutAll?.call());
    if (result == null) return;
    _throwResult(result);
  }

  @override
  Future<PasswordResetDispatchResponseDto> requestPasswordReset(
    PasswordResetRequestDto request, {
    required String idempotencyKey,
  }) async {
    final result = await _invoke(
      () =>
          onPasswordResetRequest?.call(request, idempotencyKey: idempotencyKey),
    );
    if (result is PasswordResetDispatchResponseDto) return result;
    _throwResult(result);
  }

  @override
  Future<void> confirmPasswordReset(
    ConfirmPasswordResetRequestDto request,
  ) async {
    final result = await _invoke(() => onPasswordResetConfirm?.call(request));
    if (result == null) return;
    _throwResult(result);
  }

  @override
  Future<AuthenticationResponseDto> changePassword(
    ChangePasswordRequestDto request,
  ) async {
    final result = await _invoke(() => onChangePassword?.call(request));
    if (result is AuthenticationResponseDto) return result;
    _throwResult(result);
  }

  @override
  Future<EmailChallengeResponseDto> requestEmailChange(
    RequestEmailChangeRequestDto request, {
    required String idempotencyKey,
  }) async {
    final result = await _invoke(
      () => onEmailChangeRequest?.call(request, idempotencyKey: idempotencyKey),
    );
    if (result is EmailChallengeResponseDto) return result;
    _throwResult(result);
  }

  @override
  Future<AuthenticationResponseDto> confirmEmailChange(
    ConfirmEmailChangeRequestDto request,
  ) async {
    final result = await _invoke(() => onEmailChangeConfirm?.call(request));
    if (result is AuthenticationResponseDto) return result;
    _throwResult(result);
  }
}
