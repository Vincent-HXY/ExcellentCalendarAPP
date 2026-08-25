import 'verification_credential_dto.dart';

class VerifyRegistrationRequestDto {
  const VerifyRegistrationRequestDto({
    required this.challengeId,
    required this.credential,
  });

  final String challengeId;
  final VerificationCredentialDto credential;

  Map<String, dynamic> toJson() => {
    'challenge_id': challengeId,
    'credential': credential.toJson(),
  };
}
