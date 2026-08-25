import 'package:excellent_calendar/application/auth/auth_service.dart';
import 'package:excellent_calendar/application/auth/auth_session_controller.dart';
import 'package:excellent_calendar/application/auth/change_password_controller.dart';
import 'package:excellent_calendar/application/auth/forgot_password_controller.dart';
import 'package:excellent_calendar/application/auth/reset_password_controller.dart';
import 'package:excellent_calendar/boundary_adapters/backend_api/backend_api_errors.dart';
import 'package:excellent_calendar/gateway_interfaces/refresh_token_secure_store_gateway.dart';
import 'package:excellent_calendar/native_contract/auth/password_reset_dispatch_response_dto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_auth_gateway.dart';
import 'fakes/fake_profile_cache.dart';
import 'fakes/fake_refresh_token_store.dart';
import 'fakes/fake_user_gateway.dart';
import 'fixtures/backend_api_fixtures.dart';

void main() {
  late FakeAuthGateway gateway;

  setUp(() {
    gateway = FakeAuthGateway();
  });

  group('ForgotPasswordController', () {
    test('success returns sent with resend countdown source', () async {
      gateway.onPasswordResetRequest = (request, {required idempotencyKey}) {
        expect(request.email, 'user@example.com');
        return PasswordResetDispatchResponseDto.fromJson({
          'accepted': true,
          'resend_available_at': '2026-08-01T01:01:00Z',
        });
      };
      final controller = ForgotPasswordController(
        gateway,
        now: () => DateTime.utc(2026, 8, 1, 1, 0),
      );
      controller.setEmail('user@example.com');
      final outcome = await controller.submit();
      expect(outcome, ForgotPasswordOutcome.sent);
      expect(controller.wasSent, isTrue);
      expect(controller.resendSecondsRemaining, greaterThan(0));
    });

    test('backend error maps to readable copy and keeps input', () async {
      gateway.onPasswordResetRequest = (_, {required idempotencyKey}) =>
          throw BackendApiException(
            error: apiErrorDto('API_RATE_LIMITED'),
            requestId: 'r1',
          );
      final controller = ForgotPasswordController(gateway);
      controller.setEmail('user@example.com');
      await controller.submit();
      expect(controller.formError, '操作过于频繁，请稍后再试');
      expect(controller.email, 'user@example.com');
    });

    test('invalid email is blocked locally', () async {
      final controller = ForgotPasswordController(gateway);
      controller.setEmail('not-an-email');
      await controller.submit();
      expect(controller.emailError, '邮箱格式不正确');
    });
  });

  group('ResetPasswordController', () {
    test('success clears local credentials via callback', () async {
      var cleared = 0;
      gateway.onPasswordResetConfirm = (request) async {
        expect(request.email, 'user@example.com');
        expect(request.credential.toJson(), {
          'credential_type': 'code',
          'code': '123456',
        });
        expect(request.newPassword, 'new-secret-pass');
        return null;
      };
      final controller = ResetPasswordController(
        gateway,
        onResetSucceeded: () async => cleared += 1,
        initialEmail: 'user@example.com',
      );
      controller.setCode('123456');
      controller.setNewPassword('new-secret-pass');
      controller.setConfirmPassword('new-secret-pass');
      final outcome = await controller.submit();
      expect(outcome, ResetPasswordOutcome.reset);
      expect(cleared, 1);
    });

    test('wrong code marks the code field', () async {
      gateway.onPasswordResetConfirm = (_) => throw BackendApiException(
        error: apiErrorDto('AUTH_VERIFICATION_EXPIRED'),
        requestId: 'r1',
      );
      final controller = ResetPasswordController(
        gateway,
        onResetSucceeded: () async {},
        initialEmail: 'user@example.com',
      );
      controller.setCode('123456');
      controller.setNewPassword('new-secret-pass');
      controller.setConfirmPassword('new-secret-pass');
      await controller.submit();
      expect(controller.codeError, '验证码已过期，请重新获取');
    });

    test('password policy violation marks the new password field', () async {
      gateway.onPasswordResetConfirm = (_) => throw BackendApiException(
        error: apiErrorDto('AUTH_PASSWORD_POLICY_VIOLATION'),
        requestId: 'r1',
      );
      final controller = ResetPasswordController(
        gateway,
        onResetSucceeded: () async {},
        initialEmail: 'user@example.com',
      );
      controller.setCode('123456');
      controller.setNewPassword('new-secret-pass');
      controller.setConfirmPassword('new-secret-pass');
      await controller.submit();
      expect(controller.newPasswordError, '新密码不符合要求，请更换后重试');
    });
  });

  group('ChangePasswordController', () {
    AuthService service(
      RefreshTokenSecureStoreGateway secureStore,
      AuthSessionController session,
    ) => AuthService(
      authGateway: gateway,
      userGateway: FakeUserGateway(),
      secureStore: secureStore,
      session: session,
      profileCache: FakeProfileCache(),
    );

    test('success rotates the token pair and keeps the session', () async {
      final store = FakeRefreshTokenStore();
      final session = AuthSessionController();
      session.markAuthenticated(
        accessToken: 'old-access-token-value-32-chars',
        currentUser: userDto(),
      );
      gateway.onChangePassword = (request) {
        expect(request.currentPassword, 'current-pass');
        expect(request.newPassword, 'new-secret-pass');
        return authenticationDto();
      };
      final controller = ChangePasswordController(service(store, session));
      controller.setCurrentPassword('current-pass');
      controller.setNewPassword('new-secret-pass');
      controller.setConfirmPassword('new-secret-pass');
      final outcome = await controller.submit();
      expect(outcome, ChangePasswordOutcome.changed);
      expect(session.accessToken, accessToken);
      expect(store.record!.refreshToken, refreshToken);
    });

    test('wrong current password marks the field and clears input', () async {
      final store = FakeRefreshTokenStore();
      final session = AuthSessionController();
      gateway.onChangePassword = (_) => throw BackendApiException(
        error: apiErrorDto('AUTH_CURRENT_PASSWORD_INVALID'),
        requestId: 'r1',
      );
      final controller = ChangePasswordController(service(store, session));
      controller.setCurrentPassword('wrong-pass');
      controller.setNewPassword('new-secret-pass');
      controller.setConfirmPassword('new-secret-pass');
      final outcome = await controller.submit();
      expect(outcome, ChangePasswordOutcome.failed);
      expect(controller.currentPasswordError, '当前密码不正确');
      expect(controller.currentPassword, '');
    });

    test('unchanged password marks the new password field', () async {
      final store = FakeRefreshTokenStore();
      final session = AuthSessionController();
      gateway.onChangePassword = (_) => throw BackendApiException(
        error: apiErrorDto('AUTH_PASSWORD_UNCHANGED'),
        requestId: 'r1',
      );
      final controller = ChangePasswordController(service(store, session));
      controller.setCurrentPassword('current-pass');
      controller.setNewPassword('same-pass-123');
      controller.setConfirmPassword('same-pass-123');
      await controller.submit();
      expect(controller.newPasswordError, '新密码不能与当前密码相同');
    });

    test('mismatched confirmation is rejected locally', () async {
      final controller = ChangePasswordController(
        service(FakeRefreshTokenStore(), AuthSessionController()),
      );
      controller.setCurrentPassword('current-pass');
      controller.setNewPassword('new-secret-pass');
      controller.setConfirmPassword('different-pass');
      await controller.submit();
      expect(controller.confirmPasswordError, '两次输入的密码不一致');
    });
  });
}
