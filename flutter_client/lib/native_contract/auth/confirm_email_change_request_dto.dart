import 'verification_credential_dto.dart';

class ConfirmEmailChangeRequestDto {
  const ConfirmEmailChangeRequestDto({
    required this.emailChangeRequestId,
    required this.credential,
  });

  final String emailChangeRequestId;
  final VerificationCredentialDto credential;

  Map<String, dynamic> toJson() => {
    'email_change_request_id': emailChangeRequestId,
    'credential': credential.toJson(),
  };
}
