import '../shared/contract_value.dart';

/// Sensitive Flutter-to-Android request for encrypted Refresh Token storage.
class StoreRefreshTokenRequestDto {
  const StoreRefreshTokenRequestDto({
    required this.refreshToken,
    required this.sessionId,
    required this.expiresAt,
  });

  final String refreshToken;
  final String sessionId;
  final DateTime expiresAt;

  Map<String, dynamic> toJson() => {
    'refresh_token': refreshToken,
    'session_id': sessionId,
    // schema 的 format: date-time 允许毫秒，解析端也接受毫秒，故这里保留
    // 完整精度，避免后端返回带毫秒的 expires_at 时重编码抛异常。
    'expires_at': ContractValue.formatUtcDateTime(
      expiresAt,
      field: 'StoreRefreshTokenRequest.expires_at',
    ),
  };
}
