import 'package:excellent_calendar/application/auth/auth_service.dart';
import 'package:excellent_calendar/application/auth/auth_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_auth_gateway.dart';
import 'fakes/fake_profile_cache.dart';
import 'fakes/fake_refresh_token_store.dart';
import 'fakes/fake_user_gateway.dart';
import 'fixtures/backend_api_fixtures.dart';

void main() {
  late FakeAuthGateway authGateway;
  late FakeUserGateway userGateway;
  late FakeRefreshTokenStore store;
  late FakeProfileCache cache;
  late AuthSessionController session;
  late AuthService service;

  setUp(() {
    authGateway = FakeAuthGateway();
    userGateway = FakeUserGateway();
    store = FakeRefreshTokenStore();
    cache = FakeProfileCache();
    session = AuthSessionController();
    service = AuthService(
      authGateway: authGateway,
      userGateway: userGateway,
      secureStore: store,
      session: session,
      profileCache: cache,
      now: () => DateTime.utc(2026, 8, 1, 1, 5),
    );
  });

  test(
    'establishSession stores RT, sets AT in memory, and caches the user',
    () async {
      final response = authenticationDto();
      await service.establishSession(response);
      expect(session.status, AuthStatus.authenticated);
      expect(session.accessToken, accessToken);
      expect(store.record!.refreshToken, refreshToken);
      expect(store.record!.sessionId, sessionId);
      expect(cache.cached, isNotNull);
      expect(cache.cached!.cachedAt, DateTime.utc(2026, 8, 1, 1, 5));
    },
  );

  test('refreshCurrentUser updates memory and cache', () async {
    final fresh = userDto();
    userGateway.onGetCurrentUser = () => fresh;
    final result = await service.refreshCurrentUser();
    expect(result.account.email, 'user@example.com');
    expect(session.currentUser!.account.email, 'user@example.com');
    expect(cache.writeCalls, 1);
  });

  test('clearLocalSession clears memory, Android token, and cache', () async {
    await service.establishSession(authenticationDto());
    await service.clearLocalSession();
    expect(session.status, AuthStatus.unauthenticated);
    expect(session.accessToken, isNull);
    expect(store.record, isNull);
    expect(cache.clearCalls, 1);
  });

  test('applyTokenPair rotates the stored RT and updates AT', () async {
    session.markAuthenticated(
      accessToken: 'old-access-token-value-32-chars',
      currentUser: userDto(),
    );
    await service.applyTokenPair(tokenPairDto());
    expect(session.accessToken, accessToken);
    expect(store.record!.refreshToken, refreshToken);
    expect(store.record!.expiresAt, DateTime.parse('2026-08-31T01:00:00Z'));
  });

  test(
    'store failure surfaces SecureTokenStoreException and clears session',
    () async {
      final response = authenticationDto();
      store.failStore = true;
      await expectLater(
        service.establishSession(response),
        throwsA(isA<SecureTokenStoreException>()),
      );
      expect(session.status, AuthStatus.unauthenticated);
    },
  );
}
