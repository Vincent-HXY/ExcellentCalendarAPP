import '../../gateway_interfaces/auth_gateway.dart';
import '../../gateway_interfaces/refresh_token_secure_store_gateway.dart';
import '../../native_contract/auth/logout_request_dto.dart';
import 'auth_service.dart';

/// Logout orchestration: best-effort server revocation followed by a
/// guaranteed local cleanup (memory token, Android token, user cache).
class LogoutService {
  LogoutService({
    required AuthGateway authGateway,
    required RefreshTokenSecureStoreGateway secureStore,
    required AuthService authService,
  }) : _authGateway = authGateway,
       _secureStore = secureStore,
       _authService = authService;

  final AuthGateway _authGateway;
  final RefreshTokenSecureStoreGateway _secureStore;
  final AuthService _authService;

  /// Current-device logout. The server call is best-effort; local cleanup is
  /// not.
  Future<void> logout() async {
    final read = await _secureStore.read();
    if (read.result.ok) {
      final record = read.result.data!;
      try {
        await _authGateway.logout(
          LogoutRequestDto(refreshToken: record.refreshToken),
        );
      } catch (_) {
        // Best-effort revocation; local cleanup proceeds regardless.
      }
    }
    await _authService.clearLocalSession();
  }

  /// Logout of every device, then local cleanup.
  Future<void> logoutAll() async {
    try {
      await _authGateway.logoutAll();
    } catch (_) {
      // Best-effort; local cleanup proceeds regardless.
    }
    await _authService.clearLocalSession();
  }

  /// Local-only cleanup used after a password reset (which already revoked
  /// every server session).
  Future<void> clearLocalSession() => _authService.clearLocalSession();
}
