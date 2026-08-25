import 'package:excellent_calendar/application/auth/auth_service.dart';
import 'package:excellent_calendar/application/auth/auth_session_controller.dart';
import 'package:excellent_calendar/application/auth/email_verification_controller.dart';
import 'package:excellent_calendar/boundary_adapters/backend_api/backend_api_errors.dart';
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

  AuthService service() => AuthService(
    authGateway: gateway,
    userGateway: FakeUserGateway(),
    secureStore: store,
    session: session,
    profileCache: FakeProfileCache(),
  );

  EmailVerificationController registrationController({String? codeError}) {
    gateway.onVerifyRegistration = (request) async {
      if (codeError != null) {
        throw BackendApiException(
          error: apiErrorDto(codeError),
          requestId: 'r1',
        );
      }
      return authenticationDto();
    };
    return EmailVerificationController(
      service(),
      mode: EmailVerificationMode.registration,
      challenge: challengeDto(),
      now: () => DateTime.utc(2026, 8, 1, 1, 0),
    );
  }

  setUp(() {
    gateway = FakeAuthGateway();
    store = FakeRefreshTokenStore();
    session = AuthSessionController();
  });

  test('registration verification establishes a full session', () async {
    final controller = registrationController();
    controller.setCode('123456');
    final outcome = await controller.submit();
    expect(outcome, EmailVerificationOutcome.verified);
    expect(session.status, AuthStatus.authenticated);
    expect(session.accessToken, accessToken);
    expect(store.record!.refreshToken, refreshToken);
  });

  test('wrong code surfaces a code error', () async {
    final controller = registrationController(
      codeError: 'AUTH_VERIFICATION_INVALID',
    );
    controller.setCode('123456');
    final outcome = await controller.submit();
    expect(outcome, EmailVerificationOutcome.failed);
    expect(controller.codeError, '验证码不正确');
  });

  test(
    'email change verification rotates tokens and refreshes the user',
    () async {
      var userFetched = 0;
      final userGateway = FakeUserGateway();
      userGateway.onGetCurrentUser = () {
        userFetched += 1;
        return userDto();
      };
      final emailChangeService = AuthService(
        authGateway: gateway,
        userGateway: userGateway,
        secureStore: store,
        session: session,
        profileCache: FakeProfileCache(),
      );
      session.markAuthenticated(
        accessToken: 'old-access-token-value-32-chars',
        currentUser: userDto(),
      );
      gateway.onEmailChangeConfirm = (request) {
        expect(
          request.emailChangeRequestId,
          '5cf0a9ad-dce4-4c96-b4a4-363353b076e1',
        );
        expect(request.credential.toJson(), {
          'credential_type': 'code',
          'code': '123456',
        });
        return authenticationDto();
      };
      final controller = EmailVerificationController(
        emailChangeService,
        mode: EmailVerificationMode.emailChange,
        challenge: challengeDto(
          purpose: 'email_change',
          actionId: '5cf0a9ad-dce4-4c96-b4a4-363353b076e1',
        ),
      );
      controller.setCode('123456');
      final outcome = await controller.submit();
      expect(outcome, EmailVerificationOutcome.verified);
      expect(session.accessToken, accessToken);
      expect(store.record!.refreshToken, refreshToken);
      expect(userFetched, 1);
    },
  );

  test('code validation requires exactly six digits', () async {
    final controller = registrationController();
    controller.setCode('12ab');
    await controller.submit();
    expect(controller.codeError, '验证码为 6 位数字');
  });

  test(
    'resend retries keep one idempotency key and success restarts the cooldown',
    () async {
      final keys = <String>[];
      var offline = true;
      gateway.onResendRegistration =
          (request, {required String idempotencyKey}) async {
            keys.add(idempotencyKey);
            if (offline) {
              throw const BackendTransportException(
                BackendTransportKind.network,
              );
            }
            return challengeDto(resendAvailableAt: '2026-08-01T01:02:00Z');
          };
      final controller = EmailVerificationController(
        service(),
        mode: EmailVerificationMode.registration,
        challenge: challengeDto(resendAvailableAt: '2026-08-01T00:59:00Z'),
        now: () => DateTime.utc(2026, 8, 1, 1, 0),
      )..start();
      expect(controller.canResend, isTrue);

      expect(await controller.resend(), isFalse);
      expect(controller.resendError, isNotNull);
      offline = false;
      expect(await controller.resend(), isTrue);
      expect(
        controller.challenge.resendAvailableAt,
        DateTime.parse('2026-08-01T01:02:00Z'),
      );
      expect(keys, hasLength(2));
      expect(keys[0], keys[1], reason: '同一重发操作的重试必须复用 Idempotency-Key');

      // 成功后重新进入 60s 冷却
      expect(controller.canResend, isFalse);
      expect(controller.resendSecondsRemaining, greaterThan(0));
    },
  );

  test('email change mode never allows resend', () async {
    final controller = EmailVerificationController(
      service(),
      mode: EmailVerificationMode.emailChange,
      challenge: challengeDto(
        purpose: 'email_change',
        actionId: '5cf0a9ad-dce4-4c96-b4a4-363353b076e1',
      ),
    )..start();
    expect(controller.canResend, isFalse);
    expect(await controller.resend(), isFalse);
  });

  test('duplicate submit while submitting is ignored', () async {
    var verifications = 0;
    gateway.onVerifyRegistration = (_) async {
      verifications += 1;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return authenticationDto();
    };
    final controller = EmailVerificationController(
      service(),
      mode: EmailVerificationMode.registration,
      challenge: challengeDto(),
    );
    controller.setCode('123456');
    final first = controller.submit();
    final second = controller.submit();
    expect(await first, EmailVerificationOutcome.verified);
    expect(await second, EmailVerificationOutcome.failed);
    expect(verifications, 1);
  });
}
