import '../shared/contract_json_object.dart';
import '../shared/contract_value.dart';

/// Typed context attached to a Backend API error. It never contains secrets.
class ApiErrorContextDto {
  const ApiErrorContextDto({this.verificationChallenge});

  final VerificationChallengeContext? verificationChallenge;

  factory ApiErrorContextDto.fromJson(Map<String, dynamic> json) {
    ContractJsonObject.rejectUnknownKeys(json, {
      'verification_challenge',
    }, 'ApiErrorContext');
    final raw = json['verification_challenge'];
    if (raw == null) {
      return const ApiErrorContextDto();
    }
    if (raw is! Map<String, dynamic>) {
      throw const FormatException(
        'ApiErrorContext.verification_challenge must be object or null.',
      );
    }
    return ApiErrorContextDto(
      verificationChallenge: VerificationChallengeContext.fromJson(raw),
    );
  }
}

/// A registration-verification challenge carried by AUTH_EMAIL_UNVERIFIED.
class VerificationChallengeContext {
  const VerificationChallengeContext({
    required this.challengeId,
    required this.purpose,
    required this.maskedEmail,
    required this.credentialTypes,
    required this.expiresAt,
    required this.resendAvailableAt,
  });

  final String challengeId;
  final String purpose;
  final String maskedEmail;
  final List<String> credentialTypes;
  final DateTime expiresAt;
  final DateTime resendAvailableAt;

  factory VerificationChallengeContext.fromJson(Map<String, dynamic> json) {
    ContractJsonObject.rejectUnknownKeys(json, {
      'challenge_id',
      'purpose',
      'masked_email',
      'credential_types',
      'expires_at',
      'resend_available_at',
    }, 'ApiErrorContext.verification_challenge');
    ContractJsonObject.requireKeys(json, {
      'challenge_id',
      'purpose',
      'masked_email',
      'credential_types',
      'expires_at',
      'resend_available_at',
    }, 'ApiErrorContext.verification_challenge');

    final purpose = json['purpose'];
    if (purpose != 'registration_verification') {
      throw const FormatException(
        'verification_challenge.purpose must be registration_verification.',
      );
    }
    return VerificationChallengeContext(
      challengeId: ContractValue.uuid(
        json,
        'challenge_id',
        'verification_challenge',
      ),
      purpose: 'registration_verification',
      maskedEmail: ContractValue.nonEmptyString(
        json,
        'masked_email',
        'verification_challenge',
      ),
      credentialTypes: ContractValue.stringList(
        json,
        'credential_types',
        'verification_challenge',
        allowed: const {'code', 'link_token'},
        unique: true,
        nonEmpty: true,
      ),
      expiresAt: ContractValue.utcDateTime(
        json,
        'expires_at',
        'verification_challenge',
      ),
      resendAvailableAt: ContractValue.utcDateTime(
        json,
        'resend_available_at',
        'verification_challenge',
      ),
    );
  }
}
