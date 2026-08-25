import 'verification_credential_dto.dart';

class ConfirmPasswordResetRequestDto {
  const ConfirmPasswordResetRequestDto({
    required this.email,
    required this.credential,
    required this.newPassword,
  });

  final String email;
  final VerificationCredentialDto credential;
  final String newPassword;

  Map<String, dynamic> toJson() => {
    'email': email,
    'credential': credential.toJson(),
    'new_password': newPassword,
  };
}
