import '../../boundary_adapters/backend_api/backend_api_errors.dart';
import '../../gateway_interfaces/refresh_token_secure_store_gateway.dart';
import 'auth_service.dart';
import 'auth_session_controller.dart';
import 'token_refresh_coordinator.dart';

enum StartupAuthResult { authenticated, unauthenticated, recoveryFailed }

/// Decides the startup route:
/// - no stored Refresh Token → login page;
/// - refresh succeeds → home (user refresh is best-effort);
/// - backend rejects the token → cleared state → login page;
/// - network unavailable → recovery page with a retry button.
class StartupAuthCheckUseCase {
  StartupAuthCheckUseCase({
    required RefreshTokenSecureStoreGateway secureStore,
    required TokenRefreshCoordinator refreshCoordinator,
    required AuthSessionController session,
    required AuthService authService,
  }) : _secureStore = secureStore,
       _refreshCoordinator = refreshCoordinator,
       _session = session,
       _authService = authService;

  final RefreshTokenSecureStoreGateway _secureStore;
  final TokenRefreshCoordinator _refreshCoordinator;
  final AuthSessionController _session;
  final AuthService _authService;

  Future<StartupAuthResult> run() async {
    final exists = await _secureStore.exists();
    if (!exists.result.ok) {
      // Keystore 瞬态故障（SECURE_TOKEN_STORAGE_FAILED 可重试）不能与"无
      // Refresh Token"混为一谈：进恢复页重试，避免把仍有效的会话误判为未登录。
      return StartupAuthResult.recoveryFailed;
    }
    if (!exists.result.data!.exists) {
      _session.markUnauthenticated();
      return StartupAuthResult.unauthenticated;
    }
    try {
      await _refreshCoordinator.refreshSession();
    } on SessionEndedException {
      return StartupAuthResult.unauthenticated;
    } on BackendTransportException {
      return StartupAuthResult.recoveryFailed;
    } on BackendContractException {
      return StartupAuthResult.recoveryFailed;
    } on BackendApiException {
      // The coordinator converts backend refresh failures into
      // SessionEndedException; this branch is defensive only.
      return StartupAuthResult.unauthenticated;
    }
    // The user aggregate is best-effort after a successful refresh: the
    // profile page renders its own error state when it is missing.
    try {
      await _authService.refreshCurrentUser();
    } catch (_) {
      // ignored: authenticated but user data will load on the profile page
    }
    return StartupAuthResult.authenticated;
  }
}
