import 'package:excellent_calendar/application/auth/auth_service.dart';
import 'package:excellent_calendar/application/auth/auth_session_controller.dart';
import 'package:excellent_calendar/application/auth/startup_auth_check_use_case.dart';
import 'package:excellent_calendar/application/auth/token_refresh_coordinator.dart';
import 'package:excellent_calendar/boundary_adapters/backend_api/backend_api_errors.dart';
import 'package:excellent_calendar/native_contract/auth/secure_refresh_token_record_response_dto.dart';
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
  late AuthSessionController session;
  late StartupAuthCheckUseCase useCase;

  setUp(() {
    authGateway = FakeAuthGateway();
    userGateway = FakeUserGateway();
    store = FakeRefreshTokenStore();
    session = AuthSessionController();
    final coordinator = TokenRefreshCoordinator(
      authGateway: authGateway,
      secureStore: store,
      session: session,
    );
    final authService = AuthService(
      authGateway: authGateway,
      userGateway: userGateway,
      secureStore: store,
      session: session,
      profileCache: FakeProfileCache(),
    );
    useCase = StartupAuthCheckUseCase(
      secureStore: store,
      refreshCoordinator: coordinator,
      session: session,
      authService: authService,
    );
  });

  test('no stored token → unauthenticated', () async {
    store.record = null;
    expect(await useCase.run(), StartupAuthResult.unauthenticated);
    expect(session.status, AuthStatus.unauthenticated);
  });

  test('keystore exists failure → recovery page instead of login', () async {
    store.failExists = true;
    expect(await useCase.run(), StartupAuthResult.recoveryFailed);
    expect(session.status, isNot(AuthStatus.unauthenticated));
  });

  test('refresh success → authenticated with user loaded', () async {
    store.record = SecureRefreshTokenRecordResponseDto(
      refreshToken: 'old-refresh-token-value-at-least-32-chars',
      sessionId: sessionId,
      expiresAt: DateTime.utc(2026, 8, 31),
    );
    authGateway.onRefreshSession = (_) => tokenPairDto();
    userGateway.onGetCurrentUser = () => userDto();
    expect(await useCase.run(), StartupAuthResult.authenticated);
    expect(session.status, AuthStatus.authenticated);
    expect(session.currentUser!.account.email, 'user@example.com');
    expect(store.record!.refreshToken, refreshToken);
  });

  test(
    'backend rejects the stored token → unauthenticated and token deleted',
    () async {
      store.record = SecureRefreshTokenRecordResponseDto(
        refreshToken: 'old-refresh-token-value-at-least-32-chars',
        sessionId: sessionId,
        expiresAt: DateTime.utc(2026, 8, 31),
      );
      authGateway.onRefreshSession = (_) => throw BackendApiException(
        error: apiErrorDto('AUTH_REFRESH_TOKEN_INVALID'),
        requestId: 'r1',
      );
      expect(await useCase.run(), StartupAuthResult.unauthenticated);
      expect(store.record, isNull);
    },
  );

  test('network unavailable → recoveryFailed and token retained', () async {
    store.record = SecureRefreshTokenRecordResponseDto(
      refreshToken: 'old-refresh-token-value-at-least-32-chars',
      sessionId: sessionId,
      expiresAt: DateTime.utc(2026, 8, 31),
    );
    authGateway.onRefreshSession = (_) =>
        throw const BackendTransportException(BackendTransportKind.network);
    expect(await useCase.run(), StartupAuthResult.recoveryFailed);
    expect(store.record, isNotNull);
  });

  test(
    'rate-limited refresh clears the session per the module rules',
    () async {
      store.record = SecureRefreshTokenRecordResponseDto(
        refreshToken: 'old-refresh-token-value-at-least-32-chars',
        sessionId: sessionId,
        expiresAt: DateTime.utc(2026, 8, 31),
      );
      authGateway.onRefreshSession = (_) => throw BackendApiException(
        error: apiErrorDto('API_RATE_LIMITED'),
        requestId: 'r1',
      );
      expect(await useCase.run(), StartupAuthResult.unauthenticated);
      expect(store.record, isNull);
    },
  );

  test('user fetch failure after refresh still lands authenticated', () async {
    store.record = SecureRefreshTokenRecordResponseDto(
      refreshToken: 'old-refresh-token-value-at-least-32-chars',
      sessionId: sessionId,
      expiresAt: DateTime.utc(2026, 8, 31),
    );
    authGateway.onRefreshSession = (_) => tokenPairDto();
    userGateway.onGetCurrentUser = () =>
        throw const BackendTransportException(BackendTransportKind.timeout);
    expect(await useCase.run(), StartupAuthResult.authenticated);
    expect(session.currentUser, isNull);
  });
}
