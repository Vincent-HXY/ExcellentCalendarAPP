import '../shared/contract_value.dart';

/// Sensitive record returned to Flutter only for the duration of a refresh
/// or revocation request. Never persist or log it.
class SecureRefreshTokenRecordResponseDto {
  const SecureRefreshTokenRecordResponseDto({
    required this.refreshToken,
    required this.sessionId,
    required this.expiresAt,
  });

  final String refreshToken;
  final String sessionId;
  final DateTime expiresAt;

  factory SecureRefreshTokenRecordResponseDto.fromJson(
    Map<String, dynamic> json,
  ) {
    ContractValue.requireExactKeys(json, {
      'refresh_token',
      'session_id',
      'expires_at',
    }, 'SecureRefreshTokenRecordResponse');

    final refreshToken = json['refresh_token'];
    if (refreshToken is! String ||
        refreshToken.length < 32 ||
        refreshToken.length > 8192) {
      throw const FormatException(
        'SecureRefreshTokenRecordResponse.refresh_token must be a 32..8192 string.',
      );
    }
    return SecureRefreshTokenRecordResponseDto(
      refreshToken: refreshToken,
      sessionId: ContractValue.uuid(
        json,
        'session_id',
        'SecureRefreshTokenRecordResponse',
      ),
      expiresAt: ContractValue.utcDateTime(
        json,
        'expires_at',
        'SecureRefreshTokenRecordResponse',
      ),
    );
  }
}
