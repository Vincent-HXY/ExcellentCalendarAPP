import 'package:excellent_calendar/native_contract/auth/authentication_response_dto.dart';
import 'package:excellent_calendar/native_contract/auth/email_challenge_response_dto.dart';
import 'package:excellent_calendar/native_contract/auth/registration_pending_response_dto.dart';
import 'package:excellent_calendar/native_contract/auth/token_pair_response_dto.dart';
import 'package:excellent_calendar/native_contract/common/api_error_dto.dart';
import 'package:excellent_calendar/native_contract/user/current_user_response_dto.dart';

const userId = '3c00d043-6b7c-4eca-92fd-e22a1a6728f4';
const sessionId = '62732653-c76a-40e7-bf72-bccabb54f06a';
const challengeId = '0ca1897b-2a49-4767-b673-53d9c8b39516';
const accessToken = 'opaque-access-token-value-at-least-32-characters';
const refreshToken = 'opaque-refresh-token-value-at-least-32-characters';

Map<String, Object?> userJson({String email = 'user@example.com'}) => {
  'account': {
    'id': userId,
    'email': email,
    'status': 'active',
    'email_verified_at': '2026-08-01T01:00:00Z',
    'created_at': '2026-08-01T00:55:00Z',
    'updated_at': '2026-08-01T01:00:00Z',
  },
  'profile': {
    'user_id': userId,
    'username': 'calendar_user',
    'display_name': 'Calendar User',
    'avatar': null,
    'created_at': '2026-08-01T00:55:00Z',
    'updated_at': '2026-08-01T00:55:00Z',
  },
  'preferences': {
    'user_id': userId,
    'locale': 'zh-CN',
    'timezone': 'Asia/Shanghai',
    'default_reminder_methods': ['popup'],
    'settings': {'theme': 'system'},
    'created_at': '2026-08-01T00:55:00Z',
    'updated_at': '2026-08-01T00:55:00Z',
  },
};

Map<String, Object?> tokenPairJson() => {
  'token_type': 'Bearer',
  'access_token': accessToken,
  'access_token_expires_at': '2026-08-01T01:15:00Z',
  'refresh_token': refreshToken,
  'refresh_token_expires_at': '2026-08-31T01:00:00Z',
  'session_id': sessionId,
};

Map<String, Object?> authenticationJson() => {
  'current_user': userJson(),
  'tokens': tokenPairJson(),
};

Map<String, Object?> challengeJson({
  String purpose = 'registration_verification',
  String? actionId,
  String maskedEmail = 'u***@example.com',
  String resendAvailableAt = '2026-08-01T01:01:00Z',
}) => {
  'challenge_id': challengeId,
  'action_id': actionId,
  'purpose': purpose,
  'masked_email': maskedEmail,
  'credential_types': ['code', 'link_token'],
  'expires_at': '2026-08-01T01:10:00Z',
  'resend_available_at': resendAvailableAt,
};

/// api_error_context.schema.json 的 verification_challenge：不允许 action_id 键。
Map<String, Object?> verificationChallengeContextJson() => {
  'challenge_id': challengeId,
  'purpose': 'registration_verification',
  'masked_email': 'u***@example.com',
  'credential_types': ['code', 'link_token'],
  'expires_at': '2026-08-01T01:10:00Z',
  'resend_available_at': '2026-08-01T01:01:00Z',
};

Map<String, Object?> registrationPendingJson() => {
  'account_id': userId,
  'challenge': challengeJson(),
};

Map<String, Object?> apiErrorJson(
  String code, {
  String message = 'error message',
  bool retryable = false,
  List<Map<String, Object?>> fieldErrors = const [],
  int? retryAfterSeconds,
  Map<String, Object?>? context,
}) => {
  'code': code,
  'message': message,
  'retryable': retryable,
  'field_errors': fieldErrors,
  'retry_after_seconds': retryAfterSeconds,
  'context': ?context,
};

Map<String, Object?> apiSuccess(Object data) => {
  'ok': true,
  'data': data,
  'error': null,
  'contract_version': 1,
  'request_id': 'request-fake-0001',
};

Map<String, Object?> apiFailure(
  String code, {
  List<Map<String, Object?>> fieldErrors = const [],
  Map<String, Object?>? context,
}) => {
  'ok': false,
  'data': null,
  'error': apiErrorJson(code, fieldErrors: fieldErrors, context: context),
  'contract_version': 1,
  'request_id': 'request-fake-0001',
};

CurrentUserResponseDto userDto() => CurrentUserResponseDto.fromJson(userJson());

TokenPairResponseDto tokenPairDto() =>
    TokenPairResponseDto.fromJson(tokenPairJson());

AuthenticationResponseDto authenticationDto() =>
    AuthenticationResponseDto.fromJson(authenticationJson());

EmailChallengeResponseDto challengeDto({
  String purpose = 'registration_verification',
  String? actionId,
  String resendAvailableAt = '2026-08-01T01:01:00Z',
}) => EmailChallengeResponseDto.fromJson(
  challengeJson(
    purpose: purpose,
    actionId: actionId,
    resendAvailableAt: resendAvailableAt,
  ),
);

RegistrationPendingResponseDto registrationPendingDto() =>
    RegistrationPendingResponseDto.fromJson(registrationPendingJson());

ApiErrorDto apiErrorDto(String code) =>
    ApiErrorDto.fromJson(apiErrorJson(code));
