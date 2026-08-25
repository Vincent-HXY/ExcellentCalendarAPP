import '../shared/contract_value.dart';

/// Short-lived access token plus rotating refresh token. Never log these.
class TokenPairResponseDto {
  const TokenPairResponseDto({
    required this.accessToken,
    required this.accessTokenExpiresAt,
    required this.refreshToken,
    required this.refreshTokenExpiresAt,
    required this.sessionId,
  });

  final String accessToken;
  final DateTime accessTokenExpiresAt;
  final String refreshToken;
  final DateTime refreshTokenExpiresAt;
  final String sessionId;

  factory TokenPairResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'token_type',
      'access_token',
      'access_token_expires_at',
      'refresh_token',
      'refresh_token_expires_at',
      'session_id',
    }, 'TokenPairResponse');

    if (json['token_type'] != 'Bearer') {
      throw const FormatException(
        'TokenPairResponse.token_type must be Bearer.',
      );
    }
    final accessToken = json['access_token'];
    final refreshToken = json['refresh_token'];
    if (accessToken is! String ||
        accessToken.length < 32 ||
        accessToken.length > 8192) {
      throw const FormatException(
        'TokenPairResponse.access_token must be a 32..8192 string.',
      );
    }
    if (refreshToken is! String ||
        refreshToken.length < 32 ||
        refreshToken.length > 8192) {
      throw const FormatException(
        'TokenPairResponse.refresh_token must be a 32..8192 string.',
      );
    }
    return TokenPairResponseDto(
      accessToken: accessToken,
      accessTokenExpiresAt: ContractValue.utcDateTime(
        json,
        'access_token_expires_at',
        'TokenPairResponse',
      ),
      refreshToken: refreshToken,
      refreshTokenExpiresAt: ContractValue.utcDateTime(
        json,
        'refresh_token_expires_at',
        'TokenPairResponse',
      ),
      sessionId: ContractValue.uuid(json, 'session_id', 'TokenPairResponse'),
    );
  }
}
