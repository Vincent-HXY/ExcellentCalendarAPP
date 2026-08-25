class ResendRegistrationRequestDto {
  const ResendRegistrationRequestDto({required this.challengeId});

  final String challengeId;

  Map<String, dynamic> toJson() => {'challenge_id': challengeId};
}
