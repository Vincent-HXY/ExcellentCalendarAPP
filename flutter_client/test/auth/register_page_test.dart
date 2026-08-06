import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excellent_calendar/auth/auth_controller.dart';
import 'package:excellent_calendar/auth/auth_state.dart';
import 'package:excellent_calendar/presentation/register/register_page.dart';
import 'package:excellent_calendar/auth/auth_api_client.dart';
import 'package:excellent_calendar/auth/auth_http_client.dart';
import 'package:excellent_calendar/auth/auth_refresh_token_adapter.dart';
import 'package:excellent_calendar/native_contract/common/native_result_dto.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';

/// A mock AuthApiClient that returns a configurable response for register.
class MockRegisterApiClient extends AuthApiClient {
  MockRegisterApiClient() : super(AuthHttpClient(config: AuthConfig(), refreshTokenAdapter: AuthRefreshTokenAdapter()));

  bool shouldSucceed = false;

  @override
  Future<ApiResponse<AuthResponseData>> register({
    required String email,
    required String username,
    required String displayName,
    required String password,
  }) async {
    if (shouldSucceed) {
      return ApiResponse(
        ok: true,
        data: AuthResponseData(
          id: 'new-user-id',
          email: email,
          username: username,
          displayName: displayName,
          emailVerified: false,
          accessToken: 'access-token',
          refreshToken: 'refresh-token',
          expiresIn: 900,
        ),
      );
    }
    return ApiResponse(ok: false);
  }

  @override
  Future<ApiResponse<AuthResponseData>> refreshToken({required String refreshToken}) async {
    return ApiResponse(ok: false);
  }
}

/// A mock RefreshTokenAdapter that doesn't use real storage.
class MockRefreshTokenAdapter extends AuthRefreshTokenAdapter {
  @override
  Future<NativeInvocation<OperationResponse>> store({
    required String refreshToken,
    required String sessionId,
    required String expiresAt,
  }) async {
    return NativeInvocation(
      rawResponse: {},
      result: NativeResultDto.success(OperationResponse(performed: true)),
      isNativeResult: true,
    );
  }

  @override
  Future<NativeInvocation<SecureRefreshTokenRecord>> read() async {
    return NativeInvocation(
      rawResponse: {},
      result: NativeResultDto.failure<SecureRefreshTokenRecord>(
        code: 'NOT_FOUND', message: 'No token'),
      isNativeResult: false,
    );
  }

  @override
  Future<NativeInvocation<OperationResponse>> delete() async {
    return NativeInvocation(
      rawResponse: {},
      result: NativeResultDto.success(OperationResponse(performed: true)),
      isNativeResult: true,
    );
  }

  @override
  Future<NativeInvocation<RefreshTokenPresence>> exists() async {
    return NativeInvocation(
      rawResponse: {},
      result: NativeResultDto.success(RefreshTokenPresence(exists: false)),
      isNativeResult: true,
    );
  }
}

Widget createTestApp(AuthController controller) {
  return MaterialApp(
    home: RegisterPage(authController: controller),
  );
}

void main() {
  late AuthController controller;

  setUp(() {
    final refreshTokenAdapter = MockRefreshTokenAdapter();
    final httpClient = AuthHttpClient(config: AuthConfig(), refreshTokenAdapter: refreshTokenAdapter);
    final apiClient = MockRegisterApiClient();
    controller = AuthController(
      httpClient: httpClient,
      apiClient: apiClient,
      refreshTokenAdapter: refreshTokenAdapter,
    );
  });

  tearDown(() {
    controller.dispose();
  });

  group('RegisterPage', () {
    testWidgets('should render all 5 input fields', (tester) async {
      await tester.pumpWidget(createTestApp(controller));
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsNWidgets(5));
      expect(find.text('邮箱'), findsOneWidget);
      expect(find.text('用户名'), findsOneWidget);
      expect(find.text('昵称'), findsOneWidget);
      expect(find.text('密码'), findsOneWidget);
      expect(find.text('确认密码'), findsOneWidget);
    });

    testWidgets('should validate email format', (tester) async {
      await tester.pumpWidget(createTestApp(controller));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.first, 'invalid');
      await tester.tap(find.text('注册'));
      await tester.pumpAndSettle();

      expect(find.text('邮箱格式不正确'), findsOneWidget);
    });

    testWidgets('should validate username length', (tester) async {
      await tester.pumpWidget(createTestApp(controller));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.first, 'test@example.com');
      await tester.enterText(fields.elementAt(1), 'ab');
      await tester.tap(find.text('注册'));
      await tester.pumpAndSettle();

      expect(find.text('用户名至少3个字符'), findsOneWidget);
    });

    testWidgets('should validate password length', (tester) async {
      await tester.pumpWidget(createTestApp(controller));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.first, 'test@example.com');
      await tester.enterText(fields.elementAt(1), 'validuser');
      await tester.enterText(fields.elementAt(2), 'Display Name');
      await tester.enterText(fields.elementAt(3), 'short');
      await tester.tap(find.text('注册'));
      await tester.pumpAndSettle();

      expect(find.text('密码至少8个字符'), findsOneWidget);
    });

    testWidgets('should validate password confirmation match', (tester) async {
      await tester.pumpWidget(createTestApp(controller));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.first, 'test@example.com');
      await tester.enterText(fields.elementAt(1), 'validuser');
      await tester.enterText(fields.elementAt(2), 'Display Name');
      await tester.enterText(fields.elementAt(3), 'password123');
      await tester.enterText(fields.last, 'different');
      await tester.tap(find.text('注册'));
      await tester.pumpAndSettle();

      expect(find.text('两次密码不一致'), findsOneWidget);
    });

    testWidgets('should show terms agreement error when not checked', (tester) async {
      await tester.pumpWidget(createTestApp(controller));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.first, 'test@example.com');
      await tester.enterText(fields.elementAt(1), 'validuser');
      await tester.enterText(fields.elementAt(2), 'Display Name');
      await tester.enterText(fields.elementAt(3), 'password123');
      await tester.enterText(fields.last, 'password123');
      await tester.tap(find.text('注册'));
      await tester.pumpAndSettle();

      expect(find.text('请同意用户协议'), findsOneWidget);
    });

    testWidgets('should show login link', (tester) async {
      await tester.pumpWidget(createTestApp(controller));
      await tester.pumpAndSettle();

      expect(find.text('已有账号？'), findsOneWidget);
      expect(find.text('登录'), findsOneWidget);
    });

    testWidgets('should navigate to email verification on successful register', (tester) async {
      // Create a controller with a mock that always succeeds
      final successApi = MockRegisterApiClient();
      successApi.shouldSucceed = true;
      final refreshTokenAdapter = MockRefreshTokenAdapter();
      final httpClient = AuthHttpClient(config: AuthConfig(), refreshTokenAdapter: refreshTokenAdapter);
      final successController = AuthController(
        httpClient: httpClient,
        apiClient: successApi,
        refreshTokenAdapter: refreshTokenAdapter,
      );

      await tester.pumpWidget(createTestApp(successController));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.first, 'test@example.com');
      await tester.enterText(fields.elementAt(1), 'newuser');
      await tester.enterText(fields.elementAt(2), 'Display Name');
      await tester.enterText(fields.elementAt(3), 'password123');
      await tester.enterText(fields.last, 'password123');

      await tester.tap(find.text('注册'));
      await tester.pumpAndSettle();

      expect(find.text('验证邮箱'), findsOneWidget);

      successController.dispose();
    });
  });
}