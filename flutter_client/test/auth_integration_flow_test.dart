import 'package:dio/dio.dart';
import 'package:excellent_calendar/application/auth/auth_service.dart';
import 'package:excellent_calendar/application/auth/auth_session_controller.dart';
import 'package:excellent_calendar/application/auth/email_verification_controller.dart';
import 'package:excellent_calendar/application/auth/login_controller.dart';
import 'package:excellent_calendar/application/auth/logout_service.dart';
import 'package:excellent_calendar/application/auth/register_controller.dart';
import 'package:excellent_calendar/application/auth/startup_auth_check_use_case.dart';
import 'package:excellent_calendar/application/auth/token_refresh_coordinator.dart';
import 'package:excellent_calendar/boundary_adapters/backend_api/backend_api_config.dart';
import 'package:excellent_calendar/boundary_adapters/backend_api/backend_api_errors.dart';
import 'package:excellent_calendar/boundary_adapters/backend_api/dio_backend_api_client.dart';
import 'package:excellent_calendar/data/auth/dio_auth_gateway.dart';
import 'package:excellent_calendar/data/user/dio_user_gateway.dart';
import 'package:excellent_calendar/native_contract/auth/secure_refresh_token_record_response_dto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_backend_adapter.dart';
import 'fakes/fake_profile_cache.dart';
import 'fakes/fake_refresh_token_store.dart';
import 'fixtures/backend_api_fixtures.dart';

/// Client-side walkthrough of the core flows against a Fake API transport:
/// the real dio client, real gateways, real services, real controllers.
void main() {
  late FakeBackendAdapter adapter;
  late Dio dio;
  late AuthSessionController session;
  late FakeRefreshTokenStore secureStore;
  late FakeProfileCache cache;
  late AuthService authService;
  late DioAuthGateway authGateway;
  late DioUserGateway userGateway;
  late TokenRefreshCoordinator coordinator;
  late LogoutService logoutService;

  setUp(() {
    adapter = FakeBackendAdapter();
    dio = Dio(
      BaseOptions(
        baseUrl: 'http://10.0.2.2:8080/api/v1',
        validateStatus: (_) => true,
      ),
    );
    dio.httpClientAdapter = adapter;
    session = AuthSessionController();
    secureStore = FakeRefreshTokenStore();
    cache = FakeProfileCache();
    late final DioBackendApiClient client;
    client = DioBackendApiClient(
      config: const BackendApiConfig(),
      accessTokenProvider: () => session.accessToken,
      refreshSession: () => coordinator.refreshSession(),
      onSessionEnded: () => coordinator.endSession(),
      dio: dio,
    );
    authGateway = DioAuthGateway(client);
    userGateway = DioUserGateway(client);
    authService = AuthService(
      authGateway: authGateway,
      userGateway: userGateway,
      secureStore: secureStore,
      session: session,
      profileCache: cache,
    );
    coordinator = TokenRefreshCoordinator(
      authGateway: authGateway,
      secureStore: secureStore,
      session: session,
    );
    logoutService = LogoutService(
      authGateway: authGateway,
      secureStore: secureStore,
      authService: authService,
    );
  });

  test(
    'registration then code verification establishes a durable session',
    () async {
      adapter.queue.add(
        FakeBackendResponse(body: apiSuccess(registrationPendingJson())),
      );
      final registerController = RegisterController(
        authGateway.register,
        localeProvider: () => 'zh-CN',
        timezoneProvider: () async => 'Asia/Shanghai',
      );
      registerController.setEmail('user@example.com');
      registerController.setUsername('calendar_user');
      registerController.setDisplayName('Calendar User');
      registerController.setPassword('secret-pass');
      registerController.setConfirmPassword('secret-pass');
      registerController.setAgreementAccepted(true);
      final registerOutcome = await registerController.submit();
      expect(registerOutcome, RegisterOutcome.registered);
      final registerRequest = adapter.requests.last;
      expect(registerRequest.path, '/auth/register');
      expect(registerRequest.headerIdempotencyKey, isNotNull);

      adapter.queue.add(
        FakeBackendResponse(body: apiSuccess(authenticationJson())),
      );
      final verification = EmailVerificationController(
        authService,
        mode: EmailVerificationMode.registration,
        challenge: registerController.pending!.challenge,
      );
      verification.setCode('123456');
      expect(await verification.submit(), EmailVerificationOutcome.verified);
      expect(session.status, AuthStatus.authenticated);
      expect(secureStore.record!.refreshToken, refreshToken);
      expect(cache.cached, isNotNull);

      adapter.queue.add(
        FakeBackendResponse(
          body: apiSuccess({'performed': true, 'message': null}),
        ),
      );
      await logoutService.logout();
      expect(session.status, AuthStatus.unauthenticated);
      expect(secureStore.record, isNull);
      expect(cache.cached, isNull);
    },
  );

  test('startup restores the session with a stored Refresh Token', () async {
    secureStore.record = SecureRefreshTokenRecordResponseDto(
      refreshToken: 'old-refresh-token-value-at-least-32-chars',
      sessionId: sessionId,
      expiresAt: DateTime.utc(2026, 8, 31),
    );
    adapter.queue.add(FakeBackendResponse(body: apiSuccess(tokenPairJson())));
    adapter.queue.add(FakeBackendResponse(body: apiSuccess(userJson())));

    final startup = StartupAuthCheckUseCase(
      secureStore: secureStore,
      refreshCoordinator: coordinator,
      session: session,
      authService: authService,
    );
    expect(await startup.run(), StartupAuthResult.authenticated);
    expect(session.accessToken, accessToken);
    expect(secureStore.record!.refreshToken, refreshToken);
    expect(session.currentUser!.account.email, 'user@example.com');
  });

  test(
    'expired Access Token triggers one refresh and retries the profile call',
    () async {
      secureStore.record = SecureRefreshTokenRecordResponseDto(
        refreshToken: 'old-refresh-token-value-at-least-32-chars',
        sessionId: sessionId,
        expiresAt: DateTime.utc(2026, 8, 31),
      );
      session.markAuthenticated(
        accessToken: 'expired-access-token-value-32-chars',
        currentUser: userDto(),
      );
      adapter.queue.add(
        FakeBackendResponse(body: apiFailure('API_UNAUTHENTICATED')),
      );
      adapter.queue.add(FakeBackendResponse(body: apiSuccess(tokenPairJson())));
      adapter.queue.add(FakeBackendResponse(body: apiSuccess(userJson())));

      final user = await authService.refreshCurrentUser();
      expect(user.account.email, 'user@example.com');
      expect(adapter.requests.map((r) => r.path).toList(), [
        '/users/me',
        '/auth/token/refresh',
        '/users/me',
      ]);
      expect(session.accessToken, accessToken);
      expect(secureStore.record!.refreshToken, refreshToken);
    },
  );

  test('repeated auth failure after refresh ends the session', () async {
    secureStore.record = SecureRefreshTokenRecordResponseDto(
      refreshToken: 'old-refresh-token-value-at-least-32-chars',
      sessionId: sessionId,
      expiresAt: DateTime.utc(2026, 8, 31),
    );
    session.markAuthenticated(
      accessToken: 'expired-access-token-value-32-chars',
      currentUser: userDto(),
    );
    adapter.queue.add(
      FakeBackendResponse(body: apiFailure('API_UNAUTHENTICATED')),
    );
    adapter.queue.add(FakeBackendResponse(body: apiSuccess(tokenPairJson())));
    adapter.queue.add(
      FakeBackendResponse(body: apiFailure('AUTH_SESSION_EXPIRED')),
    );

    await expectLater(
      authService.userGateway.getCurrentUser(),
      throwsA(isA<SessionEndedException>()),
    );
    expect(session.status, AuthStatus.unauthenticated);
    expect(secureStore.record, isNull);
  });

  test('login with wrong credentials surfaces the readable error', () async {
    adapter.queue.add(
      FakeBackendResponse(body: apiFailure('AUTH_INVALID_CREDENTIALS')),
    );
    final login = LoginController(authService);
    login.setEmail('user@example.com');
    login.setPassword('wrong-pass');
    expect(await login.submit(), LoginOutcome.failed);
    expect(login.formError, '邮箱或密码不正确');
    expect(login.email, 'user@example.com');
    expect(login.password, '');
  });

  // 端到端并发 401：真实 dio client + coordinator 接线，N 个并发请求只触发
  // 一次 refresh，其余复用结果并各自重试成功（family 风暴防护的实际落点）。
  test(
    'concurrent 401s trigger exactly one refresh then all succeed',
    () async {
      secureStore.record = SecureRefreshTokenRecordResponseDto(
        refreshToken: 'old-refresh-token-value-at-least-32-chars',
        sessionId: sessionId,
        expiresAt: DateTime.utc(2026, 8, 31),
      );
      session.markAuthenticated(
        accessToken: 'expired-access-token-value-32-chars',
        currentUser: userDto(),
      );

      final concurrentCount = 6;
      var profileCalls = 0;
      var refreshCalls = 0;
      adapter.handler = (request) {
        if (request.path == '/auth/token/refresh') {
          refreshCalls += 1;
          return FakeBackendResponse(body: apiSuccess(tokenPairJson()));
        }
        if (request.path == '/users/me') {
          profileCalls += 1;
          final isFirstWindow = profileCalls <= concurrentCount;
          return FakeBackendResponse(
            body: isFirstWindow
                ? apiFailure('API_UNAUTHENTICATED')
                : apiSuccess(userJson()),
          );
        }
        return FakeBackendResponse(status: 404, body: 'unexpected');
      };

      final results = await Future.wait([
        for (var i = 0; i < concurrentCount; i++)
          authService.userGateway.getCurrentUser(),
      ]);

      expect(
        results.every((u) => u.account.email == 'user@example.com'),
        isTrue,
      );
      expect(refreshCalls, 1);
      expect(session.accessToken, accessToken);
      expect(secureStore.record!.refreshToken, refreshToken);
    },
  );
}
