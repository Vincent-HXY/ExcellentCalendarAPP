import 'package:excellent_calendar/application/auth/auth_service.dart';
import 'package:excellent_calendar/application/auth/auth_session_controller.dart';
import 'package:excellent_calendar/application/auth/login_controller.dart';
import 'package:excellent_calendar/boundary_adapters/backend_api/backend_api_errors.dart';
import 'package:excellent_calendar/native_contract/common/api_error_dto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_auth_gateway.dart';
import 'fakes/fake_profile_cache.dart';
import 'fakes/fake_refresh_token_store.dart';
import 'fakes/fake_user_gateway.dart';
import 'fixtures/backend_api_fixtures.dart';

void main() {
  late FakeAuthGateway gateway;
  late LoginController controller;
  var loginCalls = 0;

  AuthService service() => AuthService(
    authGateway: gateway,
    userGateway: FakeUserGateway(),
    secureStore: FakeRefreshTokenStore(),
    session: AuthSessionController(),
    profileCache: FakeProfileCache(),
  );

  setUp(() {
    loginCalls = 0;
    gateway = FakeAuthGateway();
    gateway.onLogin = (request) {
      loginCalls += 1;
      return authenticationDto();
    };
    controller = LoginController(service());
  });

  test('successful login authenticates and returns authenticated', () async {
    controller.setEmail('user@example.com');
    controller.setPassword('secret-pass');
    final outcome = await controller.submit();
    expect(outcome, LoginOutcome.authenticated);
    expect(loginCalls, 1);
  });

  test(
    'invalid credentials keeps email, clears password, shows readable error',
    () async {
      gateway.onLogin = (_) => throw BackendApiException(
        error: apiErrorDto('AUTH_INVALID_CREDENTIALS'),
        requestId: 'r1',
      );
      controller.setEmail('user@example.com');
      controller.setPassword('secret-pass');
      final outcome = await controller.submit();
      expect(outcome, LoginOutcome.failed);
      expect(controller.email, 'user@example.com');
      expect(controller.password, '');
      expect(controller.formError, '邮箱或密码不正确');
    },
  );

  test('unverified email yields a verification challenge', () async {
    gateway.onLogin = (_) => throw BackendApiException(
      error: ApiErrorDto.fromJson(
        apiErrorJson(
          'AUTH_EMAIL_UNVERIFIED',
          context: {
            'verification_challenge': verificationChallengeContextJson(),
          },
        ),
      ),
      requestId: 'r1',
    );
    controller.setEmail('user@example.com');
    controller.setPassword('secret-pass');
    final outcome = await controller.submit();
    expect(outcome, LoginOutcome.verificationRequired);
    expect(controller.verificationChallenge!.challengeId, challengeId);
    expect(controller.verificationChallenge!.maskedEmail, 'u***@example.com');
  });

  test(
    'unverified without challenge context fails with a contract message',
    () async {
      gateway.onLogin = (_) => throw BackendApiException(
        error: apiErrorDto('AUTH_EMAIL_UNVERIFIED'),
        requestId: 'r1',
      );
      controller.setEmail('user@example.com');
      controller.setPassword('secret-pass');
      final outcome = await controller.submit();
      expect(outcome, LoginOutcome.failed);
      expect(controller.formError, '服务器返回了无法识别的响应，请稍后重试');
    },
  );

  test('transport failure maps to network copy', () async {
    gateway.onLogin = (_) =>
        throw const BackendTransportException(BackendTransportKind.network);
    controller.setEmail('user@example.com');
    controller.setPassword('secret-pass');
    await controller.submit();
    expect(controller.formError, '网络连接不可用，请检查网络后重试');
  });

  test('client-side validation blocks empty input', () async {
    final outcome = await controller.submit();
    expect(outcome, LoginOutcome.failed);
    expect(loginCalls, 0);
    expect(controller.emailError, isNotNull);
    expect(controller.passwordError, isNotNull);
  });

  test('duplicate submit is ignored while submitting', () async {
    var started = 0;
    gateway.onLogin = (_) async {
      started += 1;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return authenticationDto();
    };
    controller.setEmail('user@example.com');
    controller.setPassword('secret-pass');
    final first = controller.submit();
    final second = controller.submit();
    expect(await first, LoginOutcome.authenticated);
    expect(await second, LoginOutcome.failed);
    expect(started, 1);
  });
}
