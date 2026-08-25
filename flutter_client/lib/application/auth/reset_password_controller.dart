import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../boundary_adapters/backend_api/backend_api_errors.dart';
import '../../gateway_interfaces/auth_gateway.dart';
import '../../native_contract/auth/confirm_password_reset_request_dto.dart';
import '../../native_contract/auth/verification_credential_dto.dart';
import '../../native_contract/common/api_error_codes.dart';
import 'auth_messages.dart';
import 'auth_validators.dart';

enum ResetPasswordPhase { editing, submitting }

enum ResetPasswordOutcome { reset, failed }

class ResetPasswordController extends ChangeNotifier {
  ResetPasswordController(
    this._authGateway, {
    required this.onResetSucceeded,
    String initialEmail = '',
  }) : _email = initialEmail;

  final AuthGateway _authGateway;

  /// Called after a successful reset: clears AT, deletes the Android Refresh
  /// Token, and returns to the login page.
  final Future<void> Function() onResetSucceeded;

  ResetPasswordPhase _phase = ResetPasswordPhase.editing;
  String _email;
  String _code = '';
  String _newPassword = '';
  String _confirmPassword = '';
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _emailError;
  String? _codeError;
  String? _newPasswordError;
  String? _confirmPasswordError;
  String? _formError;
  bool _disposed = false;

  ResetPasswordPhase get phase => _phase;
  String get email => _email;
  String get code => _code;
  String get newPassword => _newPassword;
  String get confirmPassword => _confirmPassword;
  bool get obscureNew => _obscureNew;
  bool get obscureConfirm => _obscureConfirm;
  String? get emailError => _emailError;
  String? get codeError => _codeError;
  String? get newPasswordError => _newPasswordError;
  String? get confirmPasswordError => _confirmPasswordError;
  String? get formError => _formError;
  bool get isSubmitting => _phase == ResetPasswordPhase.submitting;

  void setEmail(String value) =>
      _set(() => _email = value, () => _emailError = null);
  void setCode(String value) =>
      _set(() => _code = value, () => _codeError = null);
  void setNewPassword(String value) =>
      _set(() => _newPassword = value, () => _newPasswordError = null);
  void setConfirmPassword(String value) =>
      _set(() => _confirmPassword = value, () => _confirmPasswordError = null);
  void toggleObscureNew() {
    _obscureNew = !_obscureNew;
    _notify();
  }

  void toggleObscureConfirm() {
    _obscureConfirm = !_obscureConfirm;
    _notify();
  }

  void _set(void Function() assign, void Function() clear) {
    assign();
    clear();
    _formError = null;
    _notify();
  }

  Future<ResetPasswordOutcome> submit() async {
    if (isSubmitting || !_validate()) {
      return ResetPasswordOutcome.failed;
    }
    _phase = ResetPasswordPhase.submitting;
    _formError = null;
    _notify();
    try {
      await _authGateway.confirmPasswordReset(
        ConfirmPasswordResetRequestDto(
          email: _email.trim(),
          credential: VerificationCredentialDto.code(_code),
          newPassword: _newPassword,
        ),
      );
      // The Backend revoked every session; local credentials must go too.
      await onResetSucceeded();
      return ResetPasswordOutcome.reset;
    } on BackendApiException catch (error) {
      _mapApiError(error);
      return ResetPasswordOutcome.failed;
    } on BackendTransportException catch (error) {
      _formError = transportErrorMessage(error);
      return ResetPasswordOutcome.failed;
    } on BackendContractException {
      _formError = contractErrorMessage();
      return ResetPasswordOutcome.failed;
    } finally {
      _phase = ResetPasswordPhase.editing;
      _notify();
    }
  }

  void _mapApiError(BackendApiException error) {
    switch (error.code) {
      case ApiErrorCodes.authVerificationInvalid:
      case ApiErrorCodes.authVerificationExpired:
      case ApiErrorCodes.authVerificationUsed:
        _codeError = backendErrorMessage(error.code);
      case ApiErrorCodes.authPasswordPolicyViolation:
        _newPasswordError = backendErrorMessage(error.code);
      case ApiErrorCodes.apiRateLimited:
      case ApiErrorCodes.apiInternalError:
        _formError = backendErrorMessage(error.code);
      case ApiErrorCodes.apiValidationFailed:
        final matched = applyFieldErrors(error.error.fieldErrors, {
          'email': (message) => _emailError = message,
          'code': (message) => _codeError = message,
          'new_password': (message) => _newPasswordError = message,
        });
        if (!matched) {
          _formError = backendErrorMessage(ApiErrorCodes.apiValidationFailed);
        }
      default:
        _formError = backendErrorMessage(error.code);
    }
  }

  bool _validate() {
    _emailError = AuthValidators.emailError(_email);
    _codeError = AuthValidators.verificationCodeError(_code);
    _newPasswordError = AuthValidators.passwordError(_newPassword);
    _confirmPasswordError = AuthValidators.confirmPasswordError(
      _newPassword,
      _confirmPassword,
    );
    _formError = null;
    final valid =
        _emailError == null &&
        _codeError == null &&
        _newPasswordError == null &&
        _confirmPasswordError == null;
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
