import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../boundary_adapters/backend_api/backend_api_errors.dart';
import '../../native_contract/auth/email_challenge_response_dto.dart';
import '../../native_contract/auth/login_request_dto.dart';
import '../../native_contract/common/api_error_codes.dart';
import 'auth_messages.dart';
import 'auth_service.dart';
import 'auth_validators.dart';
import 'local_test_account.dart';

enum LoginPhase { editing, submitting }

enum LoginOutcome { authenticated, verificationRequired, failed, sessionEnded }

class LoginController extends ChangeNotifier {
  LoginController(this._authService);

  final AuthService _authService;

  LoginPhase _phase = LoginPhase.editing;
  String _email = '';
  String _password = '';
  bool _obscurePassword = true;
  String? _emailError;
  String? _passwordError;
  String? _formError;
  bool _disposed = false;
  EmailChallengeResponseDto? _verificationChallenge;

  LoginPhase get phase => _phase;
  String get email => _email;
  String get password => _password;
  bool get obscurePassword => _obscurePassword;
  String? get emailError => _emailError;
  String? get passwordError => _passwordError;
  String? get formError => _formError;
  bool get isSubmitting => _phase == LoginPhase.submitting;
  EmailChallengeResponseDto? get verificationChallenge =>
      _verificationChallenge;

  void setEmail(String value) {
    if (_email == value) return;
    _email = value;
    _emailError = null;
    _formError = null;
    _notify();
  }

  void setPassword(String value) {
    if (_password == value) return;
    _password = value;
    _passwordError = null;
    _formError = null;
    _notify();
  }

  void toggleObscurePassword() {
    _obscurePassword = !_obscurePassword;
    _notify();
  }

  Future<LoginOutcome> submit() async {
    if (isSubmitting || !_validate()) {
      return LoginOutcome.failed;
    }
    _phase = LoginPhase.submitting;
    _formError = null;
    _notify();
    try {
      if (LocalTestAccount.matches(email: _email, password: _password)) {
        _authService.establishLocalTestSession();
        return LoginOutcome.authenticated;
      }
      final response = await _authService.authGateway.login(
        LoginRequestDto(email: _email.trim(), password: _password),
      );
      await _authService.establishSession(response);
      return LoginOutcome.authenticated;
    } on BackendApiException catch (error) {
      return _mapApiError(error);
    } on BackendTransportException catch (error) {
      _formError = transportErrorMessage(error);
      return LoginOutcome.failed;
    } on BackendContractException {
      _formError = contractErrorMessage();
      return LoginOutcome.failed;
    } on SessionEndedException {
      return LoginOutcome.sessionEnded;
    } on SecureTokenStoreException {
      _formError = secureStoreUnavailableMessage;
      return LoginOutcome.failed;
    } finally {
      _phase = LoginPhase.editing;
      _password = '';
      _notify();
    }
  }

  LoginOutcome _mapApiError(BackendApiException error) {
    switch (error.code) {
      case ApiErrorCodes.authInvalidCredentials:
        _formError = backendErrorMessage(error.code);
        return LoginOutcome.failed;
      case ApiErrorCodes.authEmailUnverified:
        final context = error.error.context?.verificationChallenge;
        if (context == null) {
          _formError = contractErrorMessage();
          return LoginOutcome.failed;
        }
        _verificationChallenge = EmailChallengeResponseDto(
          challengeId: context.challengeId,
          actionId: null,
          purpose: 'registration_verification',
          maskedEmail: context.maskedEmail,
          credentialTypes: context.credentialTypes,
          expiresAt: context.expiresAt,
          resendAvailableAt: context.resendAvailableAt,
        );
        return LoginOutcome.verificationRequired;
      case ApiErrorCodes.authAccountDisabled:
      case ApiErrorCodes.apiRateLimited:
      case ApiErrorCodes.apiInternalError:
        _formError = backendErrorMessage(error.code);
        return LoginOutcome.failed;
      case ApiErrorCodes.apiValidationFailed:
        final matched = applyFieldErrors(error.error.fieldErrors, {
          'email': (message) => _emailError = message,
          'password': (message) => _passwordError = message,
        });
        if (!matched) {
          _formError = backendErrorMessage(ApiErrorCodes.apiValidationFailed);
        }
        return LoginOutcome.failed;
      case ApiErrorCodes.apiUnauthenticated:
      case ApiErrorCodes.authSessionExpired:
        return LoginOutcome.sessionEnded;
      default:
        _formError = backendErrorMessage(error.code);
        return LoginOutcome.failed;
    }
  }

  bool _validate() {
    _emailError = AuthValidators.emailError(_email);
    _passwordError = AuthValidators.loginPasswordError(_password);
    _formError = null;
    final valid = _emailError == null && _passwordError == null;
    if (!valid) {
      _notify();
    }
    return valid;
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
