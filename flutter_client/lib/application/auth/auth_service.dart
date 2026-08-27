import '../../data/user/user_profile_file_cache.dart';
import '../../gateway_interfaces/auth_gateway.dart';
import '../../gateway_interfaces/refresh_token_secure_store_gateway.dart';
import '../../gateway_interfaces/user_gateway.dart';
import '../../native_contract/auth/authentication_response_dto.dart';
import '../../native_contract/auth/store_refresh_token_request_dto.dart';
import '../../native_contract/auth/token_pair_response_dto.dart';
import '../../native_contract/user/current_user_response_dto.dart';
import 'auth_session_controller.dart';
import 'local_test_account.dart';

/// Android Keystore could not persist the rotated Refresh Token.
class SecureTokenStoreException implements Exception {
  const SecureTokenStoreException();
}

/// The single authoritative implementation of "save a Token Pair and cache
/// the user". Controllers must go through here instead of repeating the
/// sequence.
class AuthService {
  AuthService({
    required AuthGateway authGateway,
    required UserGateway userGateway,
    required RefreshTokenSecureStoreGateway secureStore,
    required AuthSessionController session,
    required UserProfileCacheStore profileCache,
    DateTime Function()? now,
  }) : _authGateway = authGateway,
       _userGateway = userGateway,
       _secureStore = secureStore,
       _session = session,
       _profileCache = profileCache,
       _now = now ?? DateTime.now;

  final AuthGateway _authGateway;
  final UserGateway _userGateway;
  final RefreshTokenSecureStoreGateway _secureStore;
  final AuthSessionController _session;
  final UserProfileCacheStore _profileCache;
  final DateTime Function() _now;

  AuthGateway get authGateway => _authGateway;
  UserGateway get userGateway => _userGateway;

  /// The profile cache backing cache-first reads; exposed so Application
  /// controllers can build projections without reaching into the data layer.
  UserProfileCacheStore get profileCache => _profileCache;

  /// Starts an in-memory test session without contacting the backend or
  /// persisting credentials. The account is unavailable outside Debug builds.
  void establishLocalTestSession() {
    if (!LocalTestAccount.enabled) {
      throw StateError('Local test login is disabled outside Debug builds.');
    }
    _session.markAuthenticated(
      accessToken: LocalTestAccount.accessToken,
      currentUser: LocalTestAccount.createCurrentUser(),
    );
  }

  /// Establishes an authenticated in-memory session from a full auth
  /// response: Access Token stays in memory, the Refresh Token is written to
  /// Android Keystore, and the public profile is cached locally.
  Future<void> establishSession(AuthenticationResponseDto response) async {
    await _applyTokenPair(response.tokens);
    _session.markAuthenticated(
      accessToken: response.tokens.accessToken,
      currentUser: response.currentUser,
    );
    await _writeCacheBestEffort(response.currentUser);
  }

  /// Applies a rotated Token Pair from change-password / email-change flows
  /// while keeping the current device signed in.
  Future<void> applyTokenPair(TokenPairResponseDto pair) async {
    await _applyTokenPair(pair);
    _session.updateAccessToken(pair.accessToken);
  }

  Future<void> _applyTokenPair(TokenPairResponseDto pair) async {
    final store = await _secureStore.store(
      StoreRefreshTokenRequestDto(
        refreshToken: pair.refreshToken,
        sessionId: pair.sessionId,
        expiresAt: pair.refreshTokenExpiresAt,
      ),
    );
    if (!store.result.ok) {
      _session.clearSilently();
      throw const SecureTokenStoreException();
    }
  }

  /// Fetches the fresh user aggregate and updates memory + local cache.
  Future<CurrentUserResponseDto> refreshCurrentUser() async {
    final user = await _userGateway.getCurrentUser();
    _session.updateCurrentUser(user);
    await _writeCacheBestEffort(user);
    return user;
  }

  /// Clears every local session fact: memory token/user and Android token.
  Future<void> clearLocalSession() async {
    _session.clearSilently();
    final deleted = await _secureStore.delete();
    if (!deleted.result.ok) {
      // 删除失败会残留 RT、导致下次启动自动登录；单次重试后仍失败才放行。
      await _secureStore.delete();
    }
    await _profileCache.clear();
  }

  Future<void> _writeCacheBestEffort(CurrentUserResponseDto user) async {
    try {
      await _profileCache.write(user, _now().toUtc());
    } catch (_) {
      // The local cache is best-effort by design; a cache write failure must
      // not fail the authentication flow.
    }
  }
}
