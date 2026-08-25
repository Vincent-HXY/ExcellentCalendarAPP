import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../boundary_adapters/backend_api/backend_api_errors.dart';
import '../../native_contract/auth/change_password_request_dto.dart';
import '../../native_contract/common/api_error_codes.dart';
import 'auth_messages.dart';
import 'auth_service.dart';
import 'auth_validators.dart';

enum ChangePasswordPhase { editing, submitting }

enum ChangePasswordOutcome { changed, failed, sessionEnded }

class ChangePasswordController extends ChangeNotifier {
  ChangePasswordController(this._authService);

  final AuthService _authService;

  ChangePasswordPhase _phase = ChangePasswordPhase.editing;
  String _currentPassword = '';
  String _newPassword = '';
  String _confirmPassword = '';
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _currentPasswordError;
  String? _newPasswordError;
  String? _confirmPasswordError;
  String? _formError;
  bool _disposed = false;

  ChangePasswordPhase get phase => _phase;
  String get currentPassword => _currentPassword;
  String get newPassword => _newPassword;
  String get confirmPassword => _confirmPassword;
  bool get obscureCurrent => _obscureCurrent;
  bool get obscureNew => _obscureNew;
  bool get obscureConfirm => _obscureConfirm;
  String? get currentPasswordError => _currentPasswordError;
  String? get newPasswordError => _newPasswordError;
  String? get confirmPasswordError => _confirmPasswordError;
  String? get formError => _formError;
  bool get isSubmitting => _phase == ChangePasswordPhase.submitting;

  void setCurrentPassword(String value) =>
      _set(() => _currentPassword = value, () => _currentPasswordError = null);
  void setNewPassword(String value) =>
      _set(() => _newPassword = value, () => _newPasswordError = null);
  void setConfirmPassword(String value) =>
      _set(() => _confirmPassword = value, () => _confirmPasswordError = null);
  void toggleObscureCurrent() {
    _obscureCurrent = !_obscureCurrent;
    _notify();
  }

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

  Future<ChangePasswordOutcome> submit() async {
    if (isSubmitting || !_validate()) {
      return ChangePasswordOutcome.failed;
    }
    _phase = ChangePasswordPhase.submitting;
    _formError = null;
    _notify();
    try {
      final response = await _authService.authGateway.changePassword(
        ChangePasswordRequestDto(
          currentPassword: _currentPassword,
          newPassword: _newPassword,
        ),
      );
      // rotate_current_and_revoke_others: the new Token Pair keeps this
      // device signed in.
      await _authService.applyTokenPair(response.tokens);
      return ChangePasswordOutcome.changed;
    } on BackendApiException catch (error) {
      _mapApiError(error);
      return ChangePasswordOutcome.failed;
    } on BackendTransportException catch (error) {
      _formError = transportErrorMessage(error);
      return ChangePasswordOutcome.failed;
    } on BackendContractException {
      _formError = contractErrorMessage();
      return ChangePasswordOutcome.failed;
    } on SessionEndedException {
      return ChangePasswordOutcome.sessionEnded;
    } on SecureTokenStoreException {
      _formError = secureStoreUnavailableMessage;
      return ChangePasswordOutcome.failed;
    } finally {
      _phase = ChangePasswordPhase.editing;
      _currentPassword = '';
      _notify();
    }
  }

  void _mapApiError(BackendApiException error) {
    switch (error.code) {
      case ApiErrorCodes.authCurrentPasswordInvalid:
        _currentPasswordError = backendErrorMessage(error.code);
      case ApiErrorCodes.authPasswordPolicyViolation:
      case ApiErrorCodes.authPasswordUnchanged:
        _newPasswordError = backendErrorMessage(error.code);
      case ApiErrorCodes.apiRateLimited:
      case ApiErrorCodes.apiInternalError:
        _formError = backendErrorMessage(error.code);
      case ApiErrorCodes.apiValidationFailed:
        final matched = applyFieldErrors(error.error.fieldErrors, {
          'current_password': (message) => _currentPasswordError = message,
          'new_password': (message) => _newPasswordError = message,
        });
        if (!matched) {
          _formError = backendErrorMessage(ApiErrorCodes.apiValidationFailed);
        }
      case ApiErrorCodes.authSessionExpired:
      case ApiErrorCodes.apiUnauthenticated:
        _formError = backendErrorMessage(error.code);
      default:
        _formError = backendErrorMessage(error.code);
    }
  }

  bool _validate() {
    _currentPasswordError = AuthValidators.loginPasswordError(_currentPassword);
    _newPasswordError = AuthValidators.passwordError(_newPassword);
    _confirmPasswordError = AuthValidators.confirmPasswordError(
      _newPassword,
      _confirmPassword,
    );
    _formError = null;
    final valid =
        _currentPasswordError == null &&
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
