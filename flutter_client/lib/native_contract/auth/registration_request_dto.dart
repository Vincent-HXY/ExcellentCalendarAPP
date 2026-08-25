class RegistrationRequestDto {
  const RegistrationRequestDto({
    required this.email,
    required this.username,
    required this.displayName,
    required this.password,
    required this.locale,
    required this.timezone,
    required this.agreementVersion,
  });

  final String email;
  final String username;
  final String displayName;
  final String password;
  final String locale;
  final String timezone;
  final String agreementVersion;

  Map<String, dynamic> toJson() => {
    'email': email,
    'username': username,
    'display_name': displayName,
    'password': password,
    'locale': locale,
    'timezone': timezone,
    'agreement_version': agreementVersion,
    'agreement_accepted': true,
  };
}
