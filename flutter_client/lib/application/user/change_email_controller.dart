import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../boundary_adapters/backend_api/backend_api_errors.dart';
import '../../native_contract/auth/email_challenge_response_dto.dart';
import '../../native_contract/auth/request_email_change_request_dto.dart';
import '../../native_contract/common/api_error_codes.dart';
import '../../native_contract/user/current_user_response_dto.dart';
import '../auth/auth_messages.dart';
import '../auth/auth_service.dart';
import '../auth/auth_validators.dart';
import '../auth/idempotency_key_factory.dart';

enum ChangeEmailPhase { editing, submitting }

enum ChangeEmailOutcome { requested, failed }

class ChangeEmailController extends ChangeNotifier {
  ChangeEmailController(
    this._authService, {
    required CurrentUserResponseDto initialUser,
  }) : _currentEmail = initialUser.account.email;

  final AuthService _authService;

  ChangeEmailPhase _phase = ChangeEmailPhase.editing;
  final String _currentEmail;
  String _newEmail = '';
  String _currentPassword = '';
  bool _obscurePassword = true;
  String? _newEmailError;
  String? _currentPasswordError;
  String? _formError;
  bool _disposed = false;
  String? _idempotencyKey;
  EmailChallengeResponseDto? _challenge;

  ChangeEmailPhase get phase => _phase;
  String get currentEmail => _currentEmail;
  String get newEmail => _newEmail;
  String get currentPassword => _currentPassword;
  bool get obscurePassword => _obscurePassword;
  String? get newEmailError => _newEmailError;
  String? get currentPasswordError => _currentPasswordError;
  String? get formError => _formError;
  bool get isSubmitting => _phase == ChangeEmailPhase.submitting;
  EmailChallengeResponseDto? get challenge => _challenge;

  void setNewEmail(String value) {
    if (_newEmail == value) return;
    _newEmail = value;
    _newEmailError = null;
    _formError = null;
    _idempotencyKey = null;
    _notify();
  }

  void setCurrentPassword(String value) {
    if (_currentPassword == value) return;
    _currentPassword = value;
    _currentPasswordError = null;
    _formError = null;
    _notify();
  }

  void toggleObscurePassword() {
    _obscurePassword = !_obscurePassword;
    _notify();
  }

  Future<ChangeEmailOutcome> submit() async {
    if (isSubmitting || !_validate()) {
      return ChangeEmailOutcome.failed;
    }
    _phase = ChangeEmailPhase.submitting;
    _formError = null;
    _notify();
    _idempotencyKey ??= IdempotencyKeyFactory.generate();
    try {
      final challenge = await _authService.authGateway.requestEmailChange(
        RequestEmailChangeRequestDto(
          newEmail: _newEmail.trim(),
          currentPassword: _currentPassword,
        ),
        idempotencyKey: _idempotencyKey!,
      );
      _idempotencyKey = null;
      _challenge = challenge;
      return ChangeEmailOutcome.requested;
    } on BackendApiException catch (error) {
      _mapApiError(error);
      return ChangeEmailOutcome.failed;
    } on BackendTransportException catch (error) {
      _formError = transportErrorMessage(error);
      return ChangeEmailOutcome.failed;
    } on BackendContractException {
      _formError = contractErrorMessage();
      return ChangeEmailOutcome.failed;
    } on SessionEndedException {
      _formError = '登录状态已失效，请重新登录';
      return ChangeEmailOutcome.failed;
    } finally {
      _phase = ChangeEmailPhase.editing;
      _currentPassword = '';
      _notify();
    }
  }

  void _mapApiError(BackendApiException error) {
    switch (error.code) {
      case ApiErrorCodes.authCurrentPasswordInvalid:
        _currentPasswordError = backendErrorMessage(error.code);
      case ApiErrorCodes.authEmailAlreadyExists:
        _newEmailError = backendErrorMessage(error.code);
      case ApiErrorCodes.apiRateLimited:
      case ApiErrorCodes.apiInternalError:
        _formError = backendErrorMessage(error.code);
      case ApiErrorCodes.apiValidationFailed:
        final matched = applyFieldErrors(error.error.fieldErrors, {
          'new_email': (message) => _newEmailError = message,
          'current_password': (message) => _currentPasswordError = message,
        });
        if (!matched) {
          _formError = backendErrorMessage(ApiErrorCodes.apiValidationFailed);
        }
      default:
        _formError = backendErrorMessage(error.code);
    }
  }

  bool _validate() {
    _newEmailError = AuthValidators.emailError(_newEmail);
    _currentPasswordError = AuthValidators.loginPasswordError(_currentPassword);
    _formError = null;
    final valid = _newEmailError == null && _currentPasswordError == null;
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
