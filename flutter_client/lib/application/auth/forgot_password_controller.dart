import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../boundary_adapters/backend_api/backend_api_errors.dart';
import '../../gateway_interfaces/auth_gateway.dart';
import '../../native_contract/auth/password_reset_request_dto.dart';
import '../../native_contract/common/api_error_codes.dart';
import 'auth_messages.dart';
import 'auth_validators.dart';
import 'idempotency_key_factory.dart';

enum ForgotPasswordPhase { editing, submitting }

enum ForgotPasswordOutcome { sent, failed }

class ForgotPasswordController extends ChangeNotifier {
  ForgotPasswordController(this._authGateway, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AuthGateway _authGateway;
  final DateTime Function() _now;

  ForgotPasswordPhase _phase = ForgotPasswordPhase.editing;
  String _email = '';
  String? _emailError;
  String? _formError;
  bool _disposed = false;
  String? _idempotencyKey;
  Timer? _ticker;
  int _resendSecondsRemaining = 0;
  DateTime? _resendAvailableAt;

  ForgotPasswordPhase get phase => _phase;
  String get email => _email;
  String? get emailError => _emailError;
  String? get formError => _formError;
  bool get isSubmitting => _phase == ForgotPasswordPhase.submitting;
  bool get wasSent => _resendAvailableAt != null;
  int get resendSecondsRemaining => _resendSecondsRemaining;
  bool get canResend =>
      wasSent && _resendSecondsRemaining <= 0 && !isSubmitting;

  void setEmail(String value) {
    if (_email == value) return;
    _email = value;
    _emailError = null;
    _formError = null;
    _idempotencyKey = null;
    _notify();
  }

  Future<ForgotPasswordOutcome> submit() async {
    if (isSubmitting || !_validate()) {
      return ForgotPasswordOutcome.failed;
    }
    _phase = ForgotPasswordPhase.submitting;
    _formError = null;
    _notify();
    _idempotencyKey ??= IdempotencyKeyFactory.generate();
    try {
      final response = await _authGateway.requestPasswordReset(
        PasswordResetRequestDto(email: _email.trim()),
        idempotencyKey: _idempotencyKey!,
      );
      _idempotencyKey = null;
      _resendAvailableAt = response.resendAvailableAt;
      _scheduleTicker();
      return ForgotPasswordOutcome.sent;
    } on BackendApiException catch (error) {
      if (error.code == ApiErrorCodes.apiValidationFailed) {
        final matched = applyFieldErrors(error.error.fieldErrors, {
          'email': (message) => _emailError = message,
        });
        if (!matched) {
          _formError = backendErrorMessage(ApiErrorCodes.apiValidationFailed);
        }
      } else {
        _formError = backendErrorMessage(error.code);
      }
      return ForgotPasswordOutcome.failed;
    } on BackendTransportException catch (error) {
      _formError = transportErrorMessage(error);
      return ForgotPasswordOutcome.failed;
    } on BackendContractException {
      _formError = contractErrorMessage();
      return ForgotPasswordOutcome.failed;
    } finally {
      _phase = ForgotPasswordPhase.editing;
      _notify();
    }
  }

  bool _validate() {
    _emailError = AuthValidators.emailError(_email);
    _formError = null;
    final valid = _emailError == null;
    if (!valid) {
      _notify();
    }
    return valid;
  }

  void _scheduleTicker() {
    _ticker?.cancel();
    final availableAt = _resendAvailableAt;
    if (availableAt == null) return;
    final remaining = availableAt.difference(_now().toUtc()).inSeconds;
    _resendSecondsRemaining = remaining > 0 ? remaining : 0;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) {
        _ticker?.cancel();
        return;
      }
      final next = availableAt.difference(_now().toUtc()).inSeconds;
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
