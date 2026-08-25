import 'package:excellent_calendar/app/routing/auth_route_arguments.dart';
import 'package:excellent_calendar/application/auth/auth_service.dart';
import 'package:excellent_calendar/application/auth/auth_session_controller.dart';
import 'package:excellent_calendar/application/auth/email_verification_controller.dart';
import 'package:excellent_calendar/boundary_adapters/backend_api/backend_api_errors.dart';
import 'package:excellent_calendar/native_contract/auth/email_challenge_response_dto.dart';
import 'package:excellent_calendar/native_contract/auth/password_reset_dispatch_response_dto.dart';
import 'package:excellent_calendar/native_contract/common/api_error_dto.dart';
import 'package:excellent_calendar/presentation/auth/pages/email_verification_page.dart';
import 'package:excellent_calendar/presentation/auth/pages/forgot_password_page.dart';
import 'package:excellent_calendar/presentation/auth/pages/login_page.dart';
import 'package:excellent_calendar/presentation/auth/pages/register_page.dart';
import 'package:excellent_calendar/presentation/auth/pages/reset_password_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_auth_gateway.dart';
import 'fakes/fake_navigator.dart';
import 'fakes/fake_profile_cache.dart';
import 'fakes/fake_refresh_token_store.dart';
import 'fakes/fake_user_gateway.dart';
import 'fixtures/backend_api_fixtures.dart';

void main() {
  late FakeAuthGateway gateway;
  late FakeAuthNavigator navigator;

  AuthService service() => AuthService(
    authGateway: gateway,
    userGateway: FakeUserGateway(),
    secureStore: FakeRefreshTokenStore(),
    session: AuthSessionController(),
    profileCache: FakeProfileCache(),
  );

  setUp(() {
    gateway = FakeAuthGateway();
    navigator = FakeAuthNavigator();
  });

  group('LoginPage', () {
    testWidgets('successful login routes home', (tester) async {
      gateway.onLogin = (_) => authenticationDto();
      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(authService: service(), navigator: navigator),
        ),
      );
      await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
      await tester.enterText(find.byType(TextField).at(1), 'secret-pass');
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pump();
      await tester.pump();
      expect(navigator.goToHomeCalls, 1);
    });

    testWidgets('empty fields show inline errors and do not submit', (
      tester,
    ) async {
      var calls = 0;
      gateway.onLogin = (_) {
        calls += 1;
        return authenticationDto();
      };
      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(authService: service(), navigator: navigator),
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pump();
      expect(find.text('请输入邮箱'), findsOneWidget);
      expect(find.text('请输入密码'), findsOneWidget);
      expect(calls, 0);
    });

    testWidgets('unverified email routes to the verification page', (
      tester,
    ) async {
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
      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(authService: service(), navigator: navigator),
        ),
      );
      await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
      await tester.enterText(find.byType(TextField).at(1), 'secret-pass');
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pump();
      await tester.pump();
      expect(navigator.verificationArguments, hasLength(1));
      expect(
        navigator.verificationArguments.single.challenge.challengeId,
        challengeId,
      );
    });

    testWidgets('network failure shows readable error and keeps email', (
      tester,
    ) async {
      gateway.onLogin = (_) =>
          throw const BackendTransportException(BackendTransportKind.network);
      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(authService: service(), navigator: navigator),
        ),
      );
      await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
      await tester.enterText(find.byType(TextField).at(1), 'secret-pass');
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pump();
      await tester.pump();
      expect(find.text('网络连接不可用，请检查网络后重试'), findsOneWidget);
      final emailField = tester.widget<TextField>(find.byType(TextField).at(0));
      expect(emailField.controller!.text, 'user@example.com');
      final passwordField = tester.widget<TextField>(
        find.byType(TextField).at(1),
      );
      expect(passwordField.controller!.text, '');
    });
  });

  group('RegisterPage', () {
    Future<void> pumpRegister(WidgetTester tester) async {
      gateway.onRegister = (request, {required idempotencyKey}) async =>
          registrationPendingDto();
      await tester.pumpWidget(
        MaterialApp(
          home: RegisterPage(
            authService: service(),
            localeProvider: () => 'zh-CN',
            timezoneProvider: () async => 'Asia/Shanghai',
            navigator: navigator,
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> fillForm(WidgetTester tester) async {
      await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
      await tester.enterText(find.byType(TextField).at(1), 'calendar_user');
      await tester.enterText(find.byType(TextField).at(2), 'Calendar User');
      await tester.enterText(find.byType(TextField).at(3), 'secret-pass');
      await tester.enterText(find.byType(TextField).at(4), 'secret-pass');
      final checkbox = find.byType(Checkbox);
      await tester.ensureVisible(checkbox);
      await tester.pump();
      await tester.tap(checkbox);
      await tester.pump();
    }

    Future<void> tapRegisterSubmit(WidgetTester tester) async {
      final button = find.widgetWithText(FilledButton, '注册');
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
    }

    testWidgets('valid registration routes to verification', (tester) async {
      await pumpRegister(tester);
      await fillForm(tester);
      await tapRegisterSubmit(tester);
      await tester.pump();
      await tester.pump();
      expect(navigator.verificationArguments, hasLength(1));
      expect(
        navigator.verificationArguments.single.mode,
        EmailVerificationMode.registration,
      );
    });

    testWidgets('missing agreement blocks submission', (tester) async {
      await pumpRegister(tester);
      await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
      await tester.enterText(find.byType(TextField).at(1), 'calendar_user');
      await tester.enterText(find.byType(TextField).at(2), 'Calendar User');
      await tester.enterText(find.byType(TextField).at(3), 'secret-pass');
      await tester.enterText(find.byType(TextField).at(4), 'secret-pass');
      await tapRegisterSubmit(tester);
      await tester.pump();
      expect(find.text('请先阅读并同意用户协议'), findsOneWidget);
      expect(navigator.verificationArguments, isEmpty);
    });
  });

  group('EmailVerificationPage', () {
    testWidgets('shows masked email and verifies into home', (tester) async {
      gateway.onVerifyRegistration = (_) async => authenticationDto();
      await _pumpVerificationPage(tester, service(), navigator);
      expect(find.textContaining('u***@example.com'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('确认验证'));
      await tester.pump();
      await tester.pump();
      expect(navigator.goToHomeCalls, 1);
    });

    testWidgets('wrong code shows the code error and stays', (tester) async {
      gateway.onVerifyRegistration = (_) async => throw BackendApiException(
        error: apiErrorDto('AUTH_VERIFICATION_INVALID'),
        requestId: 'r1',
      );
      await _pumpVerificationPage(tester, service(), navigator);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('确认验证'));
      await tester.pump();
      await tester.pump();
      expect(find.text('验证码不正确'), findsOneWidget);
      expect(navigator.goToHomeCalls, 0);
    });

    testWidgets('resend button is disabled during cooldown', (tester) async {
      gateway.onVerifyRegistration = (_) async => authenticationDto();
      final challenge = challengeDto(resendAvailableAt: '2030-08-01T01:01:00Z');
      await _pumpVerificationPage(
        tester,
        service(),
        navigator,
        challenge: challenge,
      );
      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.textContaining('重新发送'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('ForgotPasswordPage', () {
    testWidgets('sends the code and shows the unified copy', (tester) async {
      gateway.onPasswordResetRequest =
          (request, {required idempotencyKey}) async =>
              PasswordResetDispatchResponseDto.fromJson({
                'accepted': true,
                'resend_available_at': '2026-08-01T01:01:00Z',
              });
      await tester.pumpWidget(
        MaterialApp(
          home: ForgotPasswordPage(
            authService: service(),
            navigator: navigator,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'user@example.com');
      await tester.tap(find.text('发送验证码'));
      await tester.pump();
      await tester.pump();
      expect(find.text('如果该邮箱已注册，系统会发送密码重置邮件'), findsOneWidget);
      expect(find.text('前往重置密码'), findsOneWidget);
    });
  });

  group('ResetPasswordPage', () {
    testWidgets('successful reset clears locally and returns to login', (
      tester,
    ) async {
      var cleared = 0;
      gateway.onPasswordResetConfirm = (_) async => null;
      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: (settings) => MaterialPageRoute(
            settings: settings,
            builder: (_) => ResetPasswordPage(
              authService: service(),
              navigator: navigator,
              onResetSucceeded: () async => cleared += 1,
            ),
          ),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).pushNamed(
                '/reset-password',
                arguments: const ResetPasswordPageArguments(
                  email: 'user@example.com',
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump();
      expect(find.text('user@example.com'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(1), '123456');
      await tester.enterText(find.byType(TextField).at(2), 'new-secret-pass');
      await tester.enterText(find.byType(TextField).at(3), 'new-secret-pass');
      await tester.tap(find.widgetWithText(FilledButton, '重置密码'));
      await tester.pump();
      await tester.pump();
      expect(cleared, 1);
      expect(navigator.goToLoginCalls, 1);
      expect(find.text('密码已重置，请用新密码登录'), findsOneWidget);
    });
  });
}

Future<void> _pumpVerificationPage(
  WidgetTester tester,
  AuthService service,
  FakeAuthNavigator navigator, {
  EmailChallengeResponseDto? challenge,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      onGenerateRoute: (settings) => MaterialPageRoute(
        settings: settings,
        builder: (_) =>
            EmailVerificationPage(authService: service, navigator: navigator),
      ),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).pushNamed(
            '/verification',
            arguments: VerificationPageArguments(
              challenge: challenge ?? challengeDto(),
              mode: EmailVerificationMode.registration,
            ),
          ),
          child: const Text('go'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pump();
  await tester.pump();
}
