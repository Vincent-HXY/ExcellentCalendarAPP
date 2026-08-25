import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../boundary_adapters/backend_api/backend_api_errors.dart';
import '../../native_contract/auth/registration_pending_response_dto.dart';
import '../../native_contract/auth/registration_request_dto.dart';
import '../../native_contract/common/api_error_codes.dart';
import '../../native_contract/common/api_field_error_dto.dart';
import 'auth_messages.dart';
import 'auth_validators.dart';
import 'idempotency_key_factory.dart';

enum RegisterPhase { editing, submitting }

enum RegisterOutcome { registered, failed }

class RegisterController extends ChangeNotifier {
  RegisterController(
    this._register, {
    required String Function() localeProvider,
    required Future<String> Function() timezoneProvider,
    String agreementVersion = 'placeholder-v1',
  }) : _localeProvider = localeProvider,
       _timezoneProvider = timezoneProvider,
       _agreementVersion = agreementVersion,
       _locale = localeProvider(),
       _timezone = '';

  final Future<RegistrationPendingResponseDto> Function(
    RegistrationRequestDto request, {
    required String idempotencyKey,
  })
  _register;

  final String Function() _localeProvider;
  final Future<String> Function() _timezoneProvider;
  final String _agreementVersion;

  RegisterPhase _phase = RegisterPhase.editing;
  String _email = '';
  String _username = '';
  String _displayName = '';
  String _password = '';
  String _confirmPassword = '';
  bool _agreementAccepted = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _emailError;
  String? _usernameError;
  String? _displayNameError;
  String? _passwordError;
  String? _confirmPasswordError;
  String? _formError;
  String _locale;
  String _timezone;
  bool _defaultsReady = false;
  bool _disposed = false;
  String? _idempotencyKey;
  RegistrationPendingResponseDto? _pending;

  RegisterPhase get phase => _phase;
  String get email => _email;
  String get username => _username;
  String get displayName => _displayName;
  String get password => _password;
  String get confirmPassword => _confirmPassword;
  bool get agreementAccepted => _agreementAccepted;
  bool get obscurePassword => _obscurePassword;
  bool get obscureConfirm => _obscureConfirm;
  String? get emailError => _emailError;
  String? get usernameError => _usernameError;
  String? get displayNameError => _displayNameError;
  String? get passwordError => _passwordError;
  String? get confirmPasswordError => _confirmPasswordError;
  String? get formError => _formError;
  String get locale => _locale;
  String get timezone => _timezone;
  bool get isSubmitting => _phase == RegisterPhase.submitting;
  RegistrationPendingResponseDto? get pending => _pending;

  /// Resolves device locale/timezone once (may run again on retry pages).
  Future<void> prepareDefaults() async {
    if (_defaultsReady) return;
    _locale = _localeProvider();
    try {
      final timezone = await _timezoneProvider();
      if (timezone.isNotEmpty) {
        _timezone = timezone;
      }
    } catch (_) {
      // Leave the field empty; validation will ask the user.
    }
    _defaultsReady = true;
    _notify();
  }

  void setEmail(String value) => _setField(() => _email = value, () {
    _emailError = null;
  });

  void setUsername(String value) => _setField(() => _username = value, () {
    _usernameError = null;
  });

  void setDisplayName(String value) =>
      _setField(() => _displayName = value, () {
        _displayNameError = null;
      });

  void setPassword(String value) => _setField(() => _password = value, () {
    _passwordError = null;
  });

  void setConfirmPassword(String value) =>
      _setField(() => _confirmPassword = value, () {
        _confirmPasswordError = null;
      });

  void setAgreementAccepted(bool value) {
    if (_agreementAccepted == value) return;
    _agreementAccepted = value;
    _notify();
  }

  void toggleObscurePassword() {
    _obscurePassword = !_obscurePassword;
    _notify();
  }

  void toggleObscureConfirm() {
    _obscureConfirm = !_obscureConfirm;
    _notify();
  }

  void _setField(void Function() assign, void Function() clearError) {
    assign();
    clearError();
    _formError = null;
    _idempotencyKey = null;
    _notify();
  }

  Future<RegisterOutcome> submit() async {
    if (isSubmitting || !_validate()) {
      return RegisterOutcome.failed;
    }
    _phase = RegisterPhase.submitting;
    _formError = null;
    _notify();
    // One stable Idempotency-Key per logical operation: reusing it when the
    // user retries the identical form prevents duplicate accounts.
    _idempotencyKey ??= IdempotencyKeyFactory.generate();
    try {
      final pending = await _register(
        RegistrationRequestDto(
          email: _email.trim(),
          username: _username.trim(),
          displayName: _displayName.trim(),
          password: _password,
          locale: _locale,
          timezone: _timezone,
          agreementVersion: _agreementVersion,
        ),
        idempotencyKey: _idempotencyKey!,
      );
      _pending = pending;
      _idempotencyKey = null;
      return RegisterOutcome.registered;
    } on BackendApiException catch (error) {
      _mapApiError(error);
      return RegisterOutcome.failed;
    } on BackendTransportException catch (error) {
      _formError = transportErrorMessage(error);
      return RegisterOutcome.failed;
    } on BackendContractException {
      _formError = contractErrorMessage();
      return RegisterOutcome.failed;
    } finally {
      _phase = RegisterPhase.editing;
      _notify();
    }
  }

  void _mapApiError(BackendApiException error) {
    switch (error.code) {
      case ApiErrorCodes.authEmailAlreadyExists:
        _emailError = backendErrorMessage(error.code);
      case ApiErrorCodes.authUsernameAlreadyExists:
        _usernameError = backendErrorMessage(error.code);
      case ApiErrorCodes.authPasswordPolicyViolation:
        _passwordError = backendErrorMessage(error.code);
      case ApiErrorCodes.apiRateLimited:
      case ApiErrorCodes.apiInternalError:
        _formError = backendErrorMessage(error.code);
      case ApiErrorCodes.apiValidationFailed:
        _applyFieldErrors(error.error.fieldErrors);
      default:
        _formError = backendErrorMessage(error.code);
    }
  }

  void _applyFieldErrors(List<ApiFieldErrorDto> fieldErrors) {
    final matched = applyFieldErrors(fieldErrors, {
      'email': (message) => _emailError = message,
      'username': (message) => _usernameError = message,
      'display_name': (message) => _displayNameError = message,
      'password': (message) => _passwordError = message,
    });
    if (!matched) {
      _formError = backendErrorMessage(ApiErrorCodes.apiValidationFailed);
    }
  }

  bool _validate() {
    _emailError = AuthValidators.emailError(_email);
    _usernameError = AuthValidators.usernameError(_username);
    _displayNameError = AuthValidators.displayNameError(_displayName);
    _passwordError = AuthValidators.passwordError(_password);
    _confirmPasswordError = AuthValidators.confirmPasswordError(
      _password,
      _confirmPassword,
    );
    _formError = null;
    if (_locale.isEmpty) {
      _locale = _localeProvider();
    }
    if (!_agreementAccepted) {
      _formError = '请先阅读并同意用户协议';
    }
    final valid =
        _emailError == null &&
        _usernameError == null &&
        _displayNameError == null &&
        _passwordError == null &&
        _confirmPasswordError == null &&
        _agreementAccepted;
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
