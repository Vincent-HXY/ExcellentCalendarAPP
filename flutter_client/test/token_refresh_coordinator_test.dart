import 'dart:async';

import 'package:excellent_calendar/application/auth/auth_service.dart';
import 'package:excellent_calendar/application/auth/auth_session_controller.dart';
import 'package:excellent_calendar/application/auth/logout_service.dart';
import 'package:excellent_calendar/application/auth/token_refresh_coordinator.dart';
import 'package:excellent_calendar/boundary_adapters/backend_api/backend_api_errors.dart';
import 'package:excellent_calendar/native_contract/auth/secure_refresh_token_record_response_dto.dart';
import 'package:excellent_calendar/native_contract/auth/token_pair_response_dto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_auth_gateway.dart';
import 'fakes/fake_profile_cache.dart';
import 'fakes/fake_refresh_token_store.dart';
import 'fakes/fake_user_gateway.dart';
import 'fixtures/backend_api_fixtures.dart';

void main() {
  late FakeAuthGateway gateway;
  late FakeRefreshTokenStore store;
  late AuthSessionController session;
  late TokenRefreshCoordinator coordinator;
  var endedCallbacks = 0;

  setUp(() {
    gateway = FakeAuthGateway();
    store = FakeRefreshTokenStore();
    session = AuthSessionController();
    endedCallbacks = 0;
    coordinator = TokenRefreshCoordinator(
      authGateway: gateway,
      secureStore: store,
      session: session,
      onSessionEnded: () => endedCallbacks += 1,
    );
    store.record = store.record; // keep default empty
  });

  test('successful refresh updates AT and rotates the stored RT', () async {
    store.record = SecureRefreshTokenRecordResponseDto(
      refreshToken: 'old-refresh-token-value-at-least-32-chars',
      sessionId: sessionId,
      expiresAt: DateTime.utc(2026, 8, 31),
    );
    gateway.onRefreshSession = (request) {
      expect(request.refreshToken, 'old-refresh-token-value-at-least-32-chars');
      return tokenPairDto();
    };
    await coordinator.refreshSession();
    expect(session.accessToken, accessToken);
    expect(session.status, AuthStatus.authenticated);
    expect(store.record!.refreshToken, refreshToken);
    expect(endedCallbacks, 0);
  });

  test('concurrent refresh calls share one backend call', () async {
    store.record = SecureRefreshTokenRecordResponseDto(
      refreshToken: 'old-refresh-token-value-at-least-32-chars',
      sessionId: sessionId,
      expiresAt: DateTime.utc(2026, 8, 31),
    );
    var completions = 0;
    gateway.onRefreshSession = (request) async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      completions += 1;
      return tokenPairDto();
    };
    await Future.wait([
      coordinator.refreshSession(),
      coordinator.refreshSession(),
      coordinator.refreshSession(),
    ]);
    expect(completions, 1);
  });

  test(
    'refresh failure with session codes clears state and deletes the token',
    () async {
      store.record = SecureRefreshTokenRecordResponseDto(
        refreshToken: 'old-refresh-token-value-at-least-32-chars',
        sessionId: sessionId,
        expiresAt: DateTime.utc(2026, 8, 31),
      );
      session.markAuthenticated(
        accessToken: 'stale-access-token-value',
        currentUser: null,
      );
      gateway.onRefreshSession = (_) => throw BackendApiException(
        error: apiErrorDto('AUTH_REFRESH_TOKEN_INVALID'),
        requestId: 'r1',
      );
      await expectLater(
        coordinator.refreshSession(),
        throwsA(isA<SessionEndedException>()),
      );
      expect(session.status, AuthStatus.unauthenticated);
      expect(session.accessToken, isNull);
      expect(store.record, isNull);
      expect(endedCallbacks, 1);
    },
  );

  test(
    'rate-limited refresh also ends the session per the module rules',
    () async {
      store.record = SecureRefreshTokenRecordResponseDto(
        refreshToken: 'old-refresh-token-value-at-least-32-chars',
        sessionId: sessionId,
        expiresAt: DateTime.utc(2026, 8, 31),
      );
      gateway.onRefreshSession = (_) => throw BackendApiException(
        error: apiErrorDto('API_RATE_LIMITED'),
        requestId: 'r1',
      );
      await expectLater(
        coordinator.refreshSession(),
        throwsA(isA<SessionEndedException>()),
      );
      expect(store.record, isNull);
    },
  );

  test(
    'transport failure during refresh keeps the session and token',
    () async {
      store.record = SecureRefreshTokenRecordResponseDto(
        refreshToken: 'old-refresh-token-value-at-least-32-chars',
        sessionId: sessionId,
        expiresAt: DateTime.utc(2026, 8, 31),
      );
      session.markAuthenticated(accessToken: 'stale-access-token-value');
      gateway.onRefreshSession = (_) =>
          throw const BackendTransportException(BackendTransportKind.network);
      await expectLater(
        coordinator.refreshSession(),
        throwsA(isA<BackendTransportException>()),
      );
      expect(session.accessToken, 'stale-access-token-value');
      expect(store.record, isNotNull);
      expect(endedCallbacks, 0);
    },
  );

  test('missing stored token ends the session', () async {
    store.record = null;
    await expectLater(
      coordinator.refreshSession(),
      throwsA(isA<SessionEndedException>()),
    );
    expect(endedCallbacks, 1);
  });

  group('logout / refresh race (P1 regression)', () {
    late FakeProfileCache cache;
    late AuthService authService;
    late LogoutService logoutService;

    setUp(() {
      cache = FakeProfileCache();
      authService = AuthService(
        authGateway: gateway,
        userGateway: FakeUserGateway(),
        secureStore: store,
        session: session,
        profileCache: cache,
      );
      logoutService = LogoutService(
        authGateway: gateway,
        secureStore: store,
        authService: authService,
      );
    });

    test(
      'logout during an in-flight refresh cannot revive the session',
      () async {
        store.record = SecureRefreshTokenRecordResponseDto(
          refreshToken: 'old-refresh-token-value-at-least-32-chars',
          sessionId: sessionId,
          expiresAt: DateTime.utc(2026, 8, 31),
        );
        session.markAuthenticated(
          accessToken: 'old-access-token-value-32-chars',
          currentUser: userDto(),
        );
        final gate = Completer<TokenPairResponseDto>();
        gateway.onRefreshSession = (_) => gate.future;
        final refreshFuture = coordinator.refreshSession();
        await waitUntil(() => gateway.refreshCalls == 1);

        // 刷新仍在途时用户退出登录。
        await logoutService.logout();
        expect(session.status, AuthStatus.unauthenticated);

        // 网络此刻才返回：旧实现会复活会话并重新写回 RT。
        gate.complete(tokenPairDto());
        await expectLater(refreshFuture, throwsA(isA<SessionEndedException>()));
        expect(session.status, AuthStatus.unauthenticated);
        expect(session.accessToken, isNull);
        expect(store.record, isNull, reason: '退出后不得重新写入 Refresh Token');
      },
    );

    test(
      'logout during the secure store write removes the just-written token',
      () async {
        store.record = SecureRefreshTokenRecordResponseDto(
          refreshToken: 'old-refresh-token-value-at-least-32-chars',
          sessionId: sessionId,
          expiresAt: DateTime.utc(2026, 8, 31),
        );
        session.markAuthenticated(
          accessToken: 'old-access-token-value-32-chars',
          currentUser: userDto(),
        );
        final storeGate = Completer<void>();
        store.storeGate = storeGate;
        gateway.onRefreshSession = (_) => tokenPairDto();
        final refreshFuture = coordinator.refreshSession();
        await waitUntil(() => store.storeCalls == 1);

        // 写入挂起时用户退出登录（清态并删除旧 RT）。
        await logoutService.logout();

        // 写入完成：协调器必须发现世代已变，删除刚写入的 RT 并终止。
        storeGate.complete();
        await expectLater(refreshFuture, throwsA(isA<SessionEndedException>()));
        expect(session.status, AuthStatus.unauthenticated);
        expect(session.accessToken, isNull);
        expect(store.record, isNull, reason: '退出后本地不得残留 Refresh Token');
      },
    );

    test('secure store failure after rotation ends the session', () async {
      store.record = SecureRefreshTokenRecordResponseDto(
        refreshToken: 'old-refresh-token-value-at-least-32-chars',
        sessionId: sessionId,
        expiresAt: DateTime.utc(2026, 8, 31),
      );
      session.markAuthenticated(
        accessToken: 'old-access-token-value-32-chars',
        currentUser: userDto(),
      );
      store.failStore = true;
      gateway.onRefreshSession = (_) => tokenPairDto();

      await expectLater(
        coordinator.refreshSession(),
        throwsA(isA<SessionEndedException>()),
      );
      expect(session.status, AuthStatus.unauthenticated);
      expect(session.accessToken, isNull);
      expect(store.record, isNull, reason: '旧 RT 必须随清态一并删除');
      expect(endedCallbacks, 1);
    });
  });
}

Future<void> waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('condition was not met in time');
}
