import 'package:excellent_calendar/application/auth/auth_service.dart';
import 'package:excellent_calendar/application/auth/auth_session_controller.dart';
import 'package:excellent_calendar/application/auth/logout_service.dart';
import 'package:excellent_calendar/boundary_adapters/backend_api/backend_api_errors.dart';
import 'package:excellent_calendar/native_contract/auth/secure_refresh_token_record_response_dto.dart';
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
  late FakeProfileCache cache;
  late LogoutService service;

  setUp(() {
    gateway = FakeAuthGateway();
    store = FakeRefreshTokenStore();
    session = AuthSessionController();
    cache = FakeProfileCache();
    final authService = AuthService(
      authGateway: gateway,
      userGateway: FakeUserGateway(),
      secureStore: store,
      session: session,
      profileCache: cache,
    );
    service = LogoutService(
      authGateway: gateway,
      secureStore: store,
      authService: authService,
    );
  });

  Future<void> primeSession() async {
    store.record = SecureRefreshTokenRecordResponseDto(
      refreshToken: refreshToken,
      sessionId: sessionId,
      expiresAt: DateTime.utc(2026, 8, 31),
    );
    session.markAuthenticated(accessToken: accessToken, currentUser: userDto());
    cache.cached = null;
  }

  test(
    'logout calls the backend with the stored RT and clears everything locally',
    () async {
      await primeSession();
      await service.logout();
      expect(gateway.logoutCalls, 1);
      expect(session.status, AuthStatus.unauthenticated);
      expect(session.accessToken, isNull);
      expect(store.record, isNull);
      expect(cache.clearCalls, 1);
    },
  );

  test('logout still clears locally when the backend call fails', () async {
    await primeSession();
    gateway.onLogout = (_) =>
        throw const BackendTransportException(BackendTransportKind.timeout);
    await service.logout();
    expect(session.status, AuthStatus.unauthenticated);
    expect(store.record, isNull);
  });

  test('logout retries once when the secure store delete fails', () async {
    await primeSession();
    store.deleteFailuresRemaining = 1;
    await service.logout();
    expect(session.status, AuthStatus.unauthenticated);
    expect(store.record, isNull);
    expect(store.deleteCalls, 2);
  });

  test('logoutAll revokes all devices then clears locally', () async {
    await primeSession();
    await service.logoutAll();
    expect(gateway.logoutAllCalls, 1);
    expect(session.status, AuthStatus.unauthenticated);
    expect(store.record, isNull);
  });

  test('clearLocalSession never calls the backend', () async {
    await primeSession();
    await service.clearLocalSession();
    expect(gateway.logoutCalls, 0);
    expect(gateway.logoutAllCalls, 0);
    expect(session.status, AuthStatus.unauthenticated);
  });
}
