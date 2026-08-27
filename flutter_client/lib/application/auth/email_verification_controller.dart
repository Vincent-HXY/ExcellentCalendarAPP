import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../boundary_adapters/backend_api/backend_api_errors.dart';
import '../../native_contract/auth/confirm_email_change_request_dto.dart';
import '../../native_contract/auth/email_challenge_response_dto.dart';
import '../../native_contract/auth/resend_registration_request_dto.dart';
import '../../native_contract/auth/verification_credential_dto.dart';
import '../../native_contract/auth/verify_registration_request_dto.dart';
import '../../native_contract/common/api_error_codes.dart';
import 'auth_messages.dart';
import 'auth_service.dart';
import 'auth_validators.dart';
import 'idempotency_key_factory.dart';

enum EmailVerificationMode { registration, emailChange }

enum EmailVerificationPhase { editing, submitting, resending }

enum EmailVerificationOutcome { verified, failed }

/// Drives the shared 6-digit verification page for registration and
/// logged-in email changes.
class EmailVerificationController extends ChangeNotifier {
  EmailVerificationController(
    this._authService, {
    required this.mode,
    required EmailChallengeResponseDto challenge,
    DateTime Function()? now,
  }) : _challenge = challenge,
       _now = now ?? DateTime.now;

  final AuthService _authService;
  final EmailVerificationMode mode;
  final DateTime Function() _now;

  EmailChallengeResponseDto _challenge;
  EmailVerificationPhase _phase = EmailVerificationPhase.editing;
  String _code = '';
  String? _codeError;
  String? _formError;
  String? _resendError;
  bool _disposed = false;
  String? _resendIdempotencyKey;
  Timer? _ticker;
  int _resendSecondsRemaining = 0;

  EmailChallengeResponseDto get challenge => _challenge;
  String get maskedEmail => _challenge.maskedEmail;
  EmailVerificationPhase get phase => _phase;
  String get code => _code;
  String? get codeError => _codeError;
  String? get formError => _formError;
  String? get resendError => _resendError;
  bool get isSubmitting => _phase == EmailVerificationPhase.submitting;
  bool get isResending => _phase == EmailVerificationPhase.resending;
  bool get canResend =>
      mode == EmailVerificationMode.registration &&
      !isSubmitting &&
      !isResending &&
      _resendSecondsRemaining <= 0;
  int get resendSecondsRemaining => _resendSecondsRemaining;

  void start() {
    _scheduleTicker();
  }

  void updateChallenge(EmailChallengeResponseDto challenge) {
    _challenge = challenge;
    _scheduleTicker();
    _notify();
  }

  void setCode(String value) {
    if (_code == value) return;
    _code = value;
    _codeError = null;
    _formError = null;
    _notify();
  }

  Future<EmailVerificationOutcome> submit() async {
    if (isSubmitting || isResending || !_validate()) {
      return EmailVerificationOutcome.failed;
    }
    _phase = EmailVerificationPhase.submitting;
    _formError = null;
    _notify();
    try {
      final credential = VerificationCredentialDto.code(_code);
      switch (mode) {
        case EmailVerificationMode.registration:
          final response = await _authService.authGateway.verifyRegistration(
            VerifyRegistrationRequestDto(
              challengeId: _challenge.challengeId,
              credential: credential,
            ),
          );
          await _authService.establishSession(response);
        case EmailVerificationMode.emailChange:
          final response = await _authService.authGateway.confirmEmailChange(
            ConfirmEmailChangeRequestDto(
              emailChangeRequestId: _challenge.actionId!,
              credential: credential,
            ),
          );
          await _authService.applyTokenPair(response.tokens);
          await _authService.refreshCurrentUser();
      }
      return EmailVerificationOutcome.verified;
    } on BackendApiException catch (error) {
      _mapApiError(error);
      return EmailVerificationOutcome.failed;
    } on BackendTransportException catch (error) {
      _formError = transportErrorMessage(error);
      return EmailVerificationOutcome.failed;
    } on BackendContractException {
      _formError = contractErrorMessage();
      return EmailVerificationOutcome.failed;
    } on SessionEndedException {
      _formError = '登录状态已失效，请重新登录';
      return EmailVerificationOutcome.failed;
    } on SecureTokenStoreException {
      _formError = secureStoreUnavailableMessage;
      return EmailVerificationOutcome.failed;
    } finally {
      _phase = EmailVerificationPhase.editing;
      _notify();
    }
  }

  /// Registration mode only: invalidates the old challenge and mails a new
  /// code after the cooldown.
  Future<bool> resend() async {
    if (!canResend) {
      return false;
    }
    _phase = EmailVerificationPhase.resending;
    _resendError = null;
    _notify();
    _resendIdempotencyKey ??= IdempotencyKeyFactory.generate();
    try {
      final challenge = await _authService.authGateway.resendRegistration(
        ResendRegistrationRequestDto(challengeId: _challenge.challengeId),
        idempotencyKey: _resendIdempotencyKey!,
      );
      _resendIdempotencyKey = null;
      _challenge = challenge;
      _code = '';
      _codeError = null;
      _formError = null;
      _scheduleTicker();
      return true;
    } on BackendApiException catch (error) {
      _resendError = backendErrorMessage(error.code);
      return false;
    } on BackendTransportException catch (error) {
      _resendError = transportErrorMessage(error);
      return false;
    } on BackendContractException {
      _resendError = contractErrorMessage();
      return false;
    } finally {
      _phase = EmailVerificationPhase.editing;
      _notify();
    }
  }

  void _mapApiError(BackendApiException error) {
    switch (error.code) {
      case ApiErrorCodes.authVerificationInvalid:
      case ApiErrorCodes.authVerificationExpired:
      case ApiErrorCodes.authVerificationUsed:
        _codeError = backendErrorMessage(error.code);
      case ApiErrorCodes.apiRateLimited:
      case ApiErrorCodes.apiInternalError:
      case ApiErrorCodes.authAccountDisabled:
        _formError = backendErrorMessage(error.code);
      case ApiErrorCodes.apiValidationFailed:
        final matched = applyFieldErrors(error.error.fieldErrors, {
          'code': (message) => _codeError = message,
        });
        if (!matched) {
          _formError = backendErrorMessage(ApiErrorCodes.apiValidationFailed);
        }
      default:
        _formError = backendErrorMessage(error.code);
    }
  }

  bool _validate() {
    _codeError = AuthValidators.verificationCodeError(_code);
    _formError = null;
    final valid = _codeError == null;
    if (!valid) {
      _notify();
    }
    return valid;
  }

  void _scheduleTicker() {
    _ticker?.cancel();
    final remaining = _challenge.resendAvailableAt
        .difference(_now().toUtc())
        .inSeconds;
    _resendSecondsRemaining = remaining > 0 ? remaining : 0;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) {
        _ticker?.cancel();
        return;
      }
      final next = _challenge.resendAvailableAt
          .difference(_now().toUtc())
          .inSeconds;
      _resendSecondsRemaining = next > 0 ? next : 0;
      if (_resendSecondsRemaining <= 0) {
        _ticker?.cancel();
      }
      _notify();
    });
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    super.dispose();
  }
}
