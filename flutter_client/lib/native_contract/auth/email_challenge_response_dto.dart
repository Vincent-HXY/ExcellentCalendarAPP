import '../shared/contract_value.dart';

/// Non-secret state needed to render and continue an email challenge.
class EmailChallengeResponseDto {
  const EmailChallengeResponseDto({
    required this.challengeId,
    required this.actionId,
    required this.purpose,
    required this.maskedEmail,
    required this.credentialTypes,
    required this.expiresAt,
    required this.resendAvailableAt,
  });

  final String challengeId;
  final String? actionId;
  final String purpose;
  final String maskedEmail;
  final List<String> credentialTypes;
  final DateTime expiresAt;
  final DateTime resendAvailableAt;

  static const purposes = {
    'registration_verification',
    'email_change',
    'password_reset',
  };

  factory EmailChallengeResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'challenge_id',
      'action_id',
      'purpose',
      'masked_email',
      'credential_types',
      'expires_at',
      'resend_available_at',
    }, 'EmailChallengeResponse');

    final purpose = json['purpose'];
    if (purpose is! String || !purposes.contains(purpose)) {
      throw FormatException('Unknown EmailChallengeResponse.purpose: $purpose');
    }
    final maskedEmail = json['masked_email'];
    if (maskedEmail is! String ||
        maskedEmail.length < 3 ||
        maskedEmail.length > 254) {
      throw const FormatException(
        'EmailChallengeResponse.masked_email must be a 3..254 string.',
      );
    }
    return EmailChallengeResponseDto(
      challengeId: ContractValue.uuid(
        json,
        'challenge_id',
        'EmailChallengeResponse',
      ),
      actionId: ContractValue.optionalUuid(
        json,
        'action_id',
        'EmailChallengeResponse',
      ),
      purpose: purpose,
      maskedEmail: maskedEmail,
      credentialTypes: ContractValue.stringList(
        json,
        'credential_types',
        'EmailChallengeResponse',
        allowed: const {'code', 'link_token'},
        unique: true,
        nonEmpty: true,
      ),
      expiresAt: ContractValue.utcDateTime(
        json,
        'expires_at',
        'EmailChallengeResponse',
      ),
      resendAvailableAt: ContractValue.utcDateTime(
        json,
        'resend_available_at',
        'EmailChallengeResponse',
      ),
    );
  }
}
