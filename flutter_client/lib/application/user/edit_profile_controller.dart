import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../boundary_adapters/backend_api/backend_api_errors.dart';
import '../../native_contract/common/api_error_codes.dart';
import '../../native_contract/user/current_user_response_dto.dart';
import '../../native_contract/user/update_current_user_request_dto.dart';
import '../auth/auth_messages.dart';
import '../auth/auth_service.dart';
import '../auth/auth_validators.dart';

enum EditProfilePhase { editing, submitting }

enum EditProfileOutcome { saved, failed }

class EditProfileController extends ChangeNotifier {
  EditProfileController(
    this._authService, {
    required CurrentUserResponseDto initialUser,
  }) : _initial = initialUser,
       _displayName = initialUser.profile.displayName,
       _username = initialUser.profile.username,
       _locale = initialUser.preferences.locale,
       _timezone = initialUser.preferences.timezone;

  final AuthService _authService;
  final CurrentUserResponseDto _initial;

  EditProfilePhase _phase = EditProfilePhase.editing;
  String _displayName;
  String _username;
  String _locale;
  String _timezone;
  String? _displayNameError;
  String? _usernameError;
  String? _localeError;
  String? _timezoneError;
  String? _formError;
  bool _disposed = false;

  EditProfilePhase get phase => _phase;
  String get displayName => _displayName;
  String get username => _username;
  String get locale => _locale;
  String get timezone => _timezone;
  String? get displayNameError => _displayNameError;
  String? get usernameError => _usernameError;
  String? get localeError => _localeError;
  String? get timezoneError => _timezoneError;
  String? get formError => _formError;
  bool get isSubmitting => _phase == EditProfilePhase.submitting;
  bool get hasChanges =>
      _displayName != _initial.profile.displayName ||
      _username != _initial.profile.username ||
      _locale != _initial.preferences.locale ||
      _timezone != _initial.preferences.timezone;
  bool get canSave => hasChanges && !isSubmitting;

  void setDisplayName(String value) =>
      _set(() => _displayName = value, () => _displayNameError = null);
  void setUsername(String value) =>
      _set(() => _username = value, () => _usernameError = null);
  void setLocale(String value) =>
      _set(() => _locale = value, () => _localeError = null);
  void setTimezone(String value) =>
      _set(() => _timezone = value, () => _timezoneError = null);

  void _set(void Function() assign, void Function() clear) {
    assign();
    clear();
    _formError = null;
    _notify();
  }

  Future<EditProfileOutcome> submit() async {
    if (isSubmitting || !_validate()) {
      return EditProfileOutcome.failed;
    }
    _phase = EditProfilePhase.submitting;
    _formError = null;
    _notify();
    try {
      await _authService.userGateway.updateCurrentUser(
        UpdateCurrentUserRequestDto(
          username: _username,
          displayName: _displayName,
          locale: _locale,
          timezone: _timezone,
        ),
      );
      // The server response is the single source of truth for the profile.
      await _authService.refreshCurrentUser();
      return EditProfileOutcome.saved;
    } on BackendApiException catch (error) {
      _mapApiError(error);
      return EditProfileOutcome.failed;
    } on BackendTransportException catch (error) {
      _formError = transportErrorMessage(error);
      return EditProfileOutcome.failed;
    } on BackendContractException {
      _formError = contractErrorMessage();
      return EditProfileOutcome.failed;
    } on SessionEndedException {
      _formError = '登录状态已失效，请重新登录';
      return EditProfileOutcome.failed;
    } finally {
      _phase = EditProfilePhase.editing;
      _notify();
    }
  }

  void _mapApiError(BackendApiException error) {
    switch (error.code) {
      case ApiErrorCodes.authUsernameAlreadyExists:
        _usernameError = backendErrorMessage(error.code);
      case ApiErrorCodes.userProfileInvalid:
        _formError = backendErrorMessage(error.code);
      case ApiErrorCodes.apiValidationFailed:
        final matched = applyFieldErrors(error.error.fieldErrors, {
          'username': (message) => _usernameError = message,
          'display_name': (message) => _displayNameError = message,
          'locale': (message) => _localeError = message,
          'timezone': (message) => _timezoneError = message,
        });
        if (!matched) {
          _formError = backendErrorMessage(ApiErrorCodes.apiValidationFailed);
        }
      default:
        _formError = backendErrorMessage(error.code);
    }
  }

  bool _validate() {
    _displayNameError = AuthValidators.displayNameError(_displayName);
    _usernameError = AuthValidators.usernameError(_username);
    _localeError = AuthValidators.localeError(_locale);
    _timezoneError = AuthValidators.timezoneError(_timezone);
    _formError = null;
    final valid =
        _displayNameError == null &&
        _usernameError == null &&
        _localeError == null &&
        _timezoneError == null;
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
