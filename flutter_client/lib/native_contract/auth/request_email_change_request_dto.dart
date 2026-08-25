class RequestEmailChangeRequestDto {
  const RequestEmailChangeRequestDto({
    required this.newEmail,
    required this.currentPassword,
  });

  final String newEmail;
  final String currentPassword;

  Map<String, dynamic> toJson() => {
    'new_email': newEmail,
    'current_password': currentPassword,
  };
}
