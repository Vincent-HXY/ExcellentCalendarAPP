class RefreshSessionRequestDto {
  const RefreshSessionRequestDto({required this.refreshToken});

  final String refreshToken;

  Map<String, dynamic> toJson() => {'refresh_token': refreshToken};
}
