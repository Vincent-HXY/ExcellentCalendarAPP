import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excellent_calendar/auth/auth_controller.dart';
import 'package:excellent_calendar/auth/auth_state.dart';
import 'package:excellent_calendar/presentation/login/login_page.dart';
import 'package:excellent_calendar/auth/auth_api_client.dart';
import 'package:excellent_calendar/auth/auth_http_client.dart';
import 'package:excellent_calendar/auth/auth_refresh_token_adapter.dart';
import 'package:excellent_calendar/native_contract/common/native_result_dto.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';

/// A mock AuthApiClient that returns a configurable response.
class MockLoginApiClient extends AuthApiClient {
  MockLoginApiClient() : super(AuthHttpClient(config: AuthConfig(), refreshTokenAdapter: AuthRefreshTokenAdapter()));

  bool shouldSucceed = false;

  @override
  Future<ApiResponse<AuthResponseData>> login({
    required String email,
    required String password,
  }) async {
    if (shouldSucceed) {
      return ApiResponse(
        ok: true,
        data: AuthResponseData(
          id: 'test-user-id',
          email: email,
          username: 'testuser',
          displayName: 'Test User',
          emailVerified: false,
          accessToken: 'access-token',
          refreshToken: 'refresh-token',
          expiresIn: 900,
        ),
      );
    }
    return ApiResponse(
      ok: false,
      error: BackendError(code: 'AUTH_INVALID_CREDENTIALS', message: 'Invalid email or password'),
    );
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
    home: LoginPage(authController: controller),
    routes: {
      '/today': (_) => const Scaffold(body: Center(child: Text('Home'))),
      '/login': (_) => const Scaffold(body: Center(child: Text('Login'))),
    },
  );
}

void main() {
  late MockLoginApiClient apiClient;
  late AuthController controller;

  setUp(() {
    apiClient = MockLoginApiClient();
    final refreshTokenAdapter = MockRefreshTokenAdapter();
    final httpClient = AuthHttpClient(config: AuthConfig(), refreshTokenAdapter: refreshTokenAdapter);
    controller = AuthController(
      httpClient: httpClient,
      apiClient: apiClient,
      refreshTokenAdapter: refreshTokenAdapter,
    );
  });

  tearDown(() {
    controller.dispose();
  });

  group('LoginPage', () {
    testWidgets('should render email and password fields', (tester) async {
      await tester.pumpWidget(createTestApp(controller));
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('邮箱'), findsOneWidget);
      expect(find.text('密码'), findsOneWidget);
    });

    testWidgets('should validate empty email', (tester) async {
      await tester.pumpWidget(createTestApp(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();

      expect(find.text('请输入邮箱'), findsOneWidget);
    });

    testWidgets('should validate invalid email format', (tester) async {
      await tester.pumpWidget(createTestApp(controller));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'invalid-email');
      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();

      expect(find.text('邮箱格式不正确'), findsOneWidget);
    });

    testWidgets('should validate empty password', (tester) async {
      await tester.pumpWidget(createTestApp(controller));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'test@example.com');
      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();

      expect(find.text('请输入密码'), findsOneWidget);
    });

    testWidgets('should navigate to /today on successful login', (tester) async {
      apiClient.shouldSucceed = true;

      await tester.pumpWidget(createTestApp(controller));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.first, 'test@example.com');
      await tester.enterText(fields.last, 'password123');
      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('should show error message on failed login', (tester) async {
      apiClient.shouldSucceed = false;

      await tester.pumpWidget(createTestApp(controller));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.first, 'test@example.com');
      await tester.enterText(fields.last, 'wrong-password');
      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();

      // Should show error message
      expect(find.text('邮箱或密码错误'), findsOneWidget);
    });

    testWidgets('should show forgot password link', (tester) async {
      await tester.pumpWidget(createTestApp(controller));
      await tester.pumpAndSettle();

      expect(find.text('忘记密码？'), findsOneWidget);
    });

    testWidgets('should show register link', (tester) async {
      await tester.pumpWidget(createTestApp(controller));
      await tester.pumpAndSettle();

      expect(find.text('还没有账号？'), findsOneWidget);
      expect(find.text('注册'), findsOneWidget);
    });
  });
}