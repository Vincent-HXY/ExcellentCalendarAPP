/// Exactly one user-supplied credential for an email action challenge.
class VerificationCredentialDto {
  const VerificationCredentialDto._(this._json);

  final Map<String, dynamic> _json;

  factory VerificationCredentialDto.code(String code) {
    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      throw ArgumentError.value(
        code,
        'code',
        'Verification code must be exactly 6 digits.',
      );
    }
    return VerificationCredentialDto._({
      'credential_type': 'code',
      'code': code,
    });
  }

  factory VerificationCredentialDto.linkToken(String linkToken) {
    if (linkToken.length < 32 || linkToken.length > 512) {
      throw ArgumentError.value(
        linkToken,
        'linkToken',
        'Link token must be a 32..512 string.',
      );
    }
    return VerificationCredentialDto._({
      'credential_type': 'link_token',
      'link_token': linkToken,
    });
  }

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(_json);
}
