import 'dart:async';

import '../../boundary_adapters/backend_api/backend_api_errors.dart';
import '../../gateway_interfaces/auth_gateway.dart';
import '../../gateway_interfaces/refresh_token_secure_store_gateway.dart';
import '../../native_contract/auth/refresh_session_request_dto.dart';
import '../../native_contract/auth/store_refresh_token_request_dto.dart';
import '../../native_contract/auth/token_pair_response_dto.dart';
import 'auth_session_controller.dart';

/// Coordinates the single-flight Refresh Token rotation.
///
/// Concurrent 401s share exactly one refresh call; after it succeeds the
/// callers retry their original requests. Any backend failure destroys the
/// local session (per the module rules), transport failures do not.
class TokenRefreshCoordinator {
  TokenRefreshCoordinator({
    required AuthGateway authGateway,
    required RefreshTokenSecureStoreGateway secureStore,
    required AuthSessionController session,
    void Function()? onSessionEnded,
  }) : _authGateway = authGateway,
       _secureStore = secureStore,
       _session = session,
       _onSessionEnded = onSessionEnded;

  final AuthGateway _authGateway;
  final RefreshTokenSecureStoreGateway _secureStore;
  final AuthSessionController _session;
  final void Function()? _onSessionEnded;

  Future<void>? _inFlight;
  bool _ending = false;

  /// Single-flight refresh entry used by the dio client.
  Future<void> refreshSession() {
    return _inFlight ??= _doRefresh().whenComplete(() {
      _inFlight = null;
    });
  }

  /// Public teardown path used by the API client when a retried request still
  /// fails: clears every local session fact and deletes the stored token.
  Future<void> endSession() async {
    if (_ending) return;
    _ending = true;
    try {
      _session.clearSilently();
      await _secureStore.delete();
    } finally {
      _onSessionEnded?.call();
      _ending = false;
    }
  }

  Future<void> _doRefresh() async {
    // 捕获本次刷新所属的会话世代：退出/重置会递增世代，任何落后于清态的
    // 异步结果都必须被丢弃，不得复活内存会话或把 RT 写回安全存储。
    final generation = _session.generation;
    final read = await _secureStore.read();
    if (_session.generation != generation) {
      // 会话在读取期间被清除：本地清理已由清除方完成，直接终止。
      throw const SessionEndedException('session ended during refresh');
    }
    if (!read.result.ok) {
      await endSession();
      throw const SessionEndedException('refresh token unavailable');
    }
    final record = read.result.data!;
    final TokenPairResponseDto pair;
    try {
      pair = await _authGateway.refreshSession(
        RefreshSessionRequestDto(refreshToken: record.refreshToken),
      );
    } on BackendApiException catch (error) {
      // 模块规则：刷新失败统一清态（含限流/服务器错误），避免半死会话。
      await endSession();
      throw SessionEndedException(error.code);
    }
    if (_session.generation != generation) {
      // 会话已在轮换期间被清除（退出/重置）：服务端旧 RT 已被消费、本地
      // RT 已被清除，这里丢弃新 Token Pair，不复活、不写回。
      throw const SessionEndedException('session ended during refresh');
    }
    // 先写回新 RT 再启用新 AT：避免“新 AT 已生效但 RT 未落盘”的半死窗口。
    final store = await _secureStore.store(
      StoreRefreshTokenRequestDto(
        refreshToken: pair.refreshToken,
        sessionId: pair.sessionId,
        expiresAt: pair.refreshTokenExpiresAt,
      ),
    );
    if (!store.result.ok) {
      // 服务端已完成轮换而新 RT 未落盘：统一清态并删除旧 RT。否则下次启动
      // 用旧 RT 刷新会触发 AUTH_REFRESH_TOKEN_REUSED 撤销整个 token family。
      await endSession();
      throw const SessionEndedException('secure token storage failed');
    }
    if (_session.generation != generation) {
      // 存储期间发生退出：删除刚写入的 RT，保证退出后本地无凭据残留。
      await _secureStore.delete();
      throw const SessionEndedException('session ended during refresh');
    }
    _session.updateAccessToken(pair.accessToken);
  }
}
