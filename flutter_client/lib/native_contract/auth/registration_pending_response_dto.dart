import 'email_challenge_response_dto.dart';
import '../shared/contract_value.dart';

/// Registration succeeded but authentication is blocked until verification.
class RegistrationPendingResponseDto {
  const RegistrationPendingResponseDto({
    required this.accountId,
    required this.challenge,
  });

  final String accountId;
  final EmailChallengeResponseDto challenge;

  factory RegistrationPendingResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'account_id',
      'challenge',
    }, 'RegistrationPendingResponse');
    final challenge = json['challenge'];
    if (challenge is! Map<String, dynamic>) {
      throw const FormatException(
        'RegistrationPendingResponse.challenge must be object.',
      );
    }
    return RegistrationPendingResponseDto(
      accountId: ContractValue.uuid(
        json,
        'account_id',
        'RegistrationPendingResponse',
      ),
      challenge: EmailChallengeResponseDto.fromJson(challenge),
    );
  }
}
