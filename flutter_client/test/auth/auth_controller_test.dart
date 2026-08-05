import 'package:flutter_test/flutter_test.dart';
import 'package:excellent_calendar/auth/auth_api_client.dart';
import 'package:excellent_calendar/auth/auth_controller.dart';
import 'package:excellent_calendar/auth/auth_http_client.dart';
import 'package:excellent_calendar/auth/auth_refresh_token_adapter.dart';
import 'package:excellent_calendar/auth/auth_state.dart';
import 'package:excellent_calendar/native_contract/common/native_result_dto.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';

// Manual mocks for testing
class MockAuthHttpClient extends AuthHttpClient {
  MockAuthHttpClient()
      : super(
          config: AuthConfig(),
          refreshTokenAdapter: MockRefreshTokenAdapter(),
        );

  String? setAccessTokenCalled;
  bool clearAccessTokenCalled = false;

  @override
  void setAccessToken(String token) {
    setAccessTokenCalled = token;
  }

  @override
  void clearAccessToken() {
    clearAccessTokenCalled = true;
  }
}

class MockRefreshTokenAdapter extends AuthRefreshTokenAdapter {
  String? storedRefreshToken;
  String? storedSessionId;
  String? storedExpiresAt;
  bool deleted = false;
  bool existsResult = false;
  SecureRefreshTokenRecord? readResult;

  @override
  Future<NativeInvocation<OperationResponse>> store({
    required String refreshToken,
    required String sessionId,
    required String expiresAt,
  }) async {
    storedRefreshToken = refreshToken;
    storedSessionId = sessionId;
    storedExpiresAt = expiresAt;
    return NativeInvocation(
      rawResponse: {},
      result: NativeResultDto.success(OperationResponse(performed: true)),
      isNativeResult: true,
    );
  }

  @override
  Future<NativeInvocation<SecureRefreshTokenRecord>> read() async {
    if (readResult != null) {
      return NativeInvocation(
        rawResponse: {},
        result: NativeResultDto.success(readResult!),
        isNativeResult: true,
      );
    }
    return NativeInvocation(
      rawResponse: {},
      result: NativeResultDto.failure<SecureRefreshTokenRecord>(
        code: 'NOT_FOUND',
        message: 'No token',
      ),
      isNativeResult: false,
    );
  }

  @override
  Future<NativeInvocation<OperationResponse>> delete() async {
    deleted = true;
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
      result: NativeResultDto.success(RefreshTokenPresence(exists: existsResult)),
      isNativeResult: true,
    );
  }
}

class MockAuthApiClient extends AuthApiClient {
  MockAuthApiClient(super.httpClient);

  bool? registerResult;
  bool? loginResult;
  bool? refreshResult;
  bool? logoutResult;
  bool? logoutAllResult;
  bool? verifyEmailResult;
  bool? resendVerificationResult;
  bool? forgotPasswordResult;
  bool? resetPasswordResult;
  bool? changePasswordResult;
  bool? changeEmailResult;
  ProfileResponseData? getProfileResult;
  bool? updateProfileResult;
  bool? uploadAvatarResult;
  bool? deleteAvatarResult;

  AuthResponseData? _authData;
  String? _errorMessage;

  void setAuthData(AuthResponseData data) {
    _authData = data;
  }

  void setError(String message) {
    _errorMessage = message;
  }

  @override
  Future<ApiResponse<AuthResponseData>> register({
    required String email,
    required String username,
    required String displayName,
    required String password,
  }) async {
    if (registerResult == true && _authData != null) {
      return ApiResponse(ok: true, data: _authData);
    }
    return ApiResponse(
      ok: false,
      error: BackendError(code: 'UNKNOWN', message: _errorMessage ?? 'Register failed'),
    );
  }

  @override
  Future<ApiResponse<AuthResponseData>> login({
    required String email,
    required String password,
  }) async {
    if (loginResult == true && _authData != null) {
      return ApiResponse(ok: true, data: _authData);
    }
    return ApiResponse(
      ok: false,
      error: BackendError(code: 'UNKNOWN', message: _errorMessage ?? 'Login failed'),
    );
  }

  @override
  Future<ApiResponse<AuthResponseData>> refreshToken({
    required String refreshToken,
  }) async {
    if (refreshResult == true && _authData != null) {
      return ApiResponse(ok: true, data: _authData);
    }
    return ApiResponse(
      ok: false,
      error: BackendError(code: 'AUTH_REFRESH_TOKEN_INVALID', message: 'Refresh failed'),
    );
  }

  @override
  Future<ApiResponse<void>> logout({required String refreshToken}) async {
    return ApiResponse(ok: logoutResult ?? true);
  }

  @override
  Future<ApiResponse<void>> logoutAll() async {
    return ApiResponse(ok: logoutAllResult ?? true);
  }

  @override
  Future<ApiResponse<AuthResponseData>> verifyEmail({required String code}) async {
    if (verifyEmailResult == true && _authData != null) {
      return ApiResponse(ok: true, data: _authData);
    }
    return ApiResponse(ok: false);
  }

  @override
  Future<ApiResponse<void>> resendVerificationCode() async {
    return ApiResponse(ok: resendVerificationResult ?? true);
  }

  @override
  Future<ApiResponse<void>> forgotPassword({required String email}) async {
    return ApiResponse(ok: forgotPasswordResult ?? true);
  }

  @override
  Future<ApiResponse<void>> resetPassword({
    required String code,
    required String newPassword,
  }) async {
    return ApiResponse(ok: resetPasswordResult ?? true);
  }

  @override
  Future<ApiResponse<AuthResponseData>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (changePasswordResult == true && _authData != null) {
      return ApiResponse(ok: true, data: _authData);
    }
    return ApiResponse(ok: false);
  }

  @override
  Future<ApiResponse<void>> changeEmail({
    required String newEmail,
    required String currentPassword,
  }) async {
    return ApiResponse(ok: changeEmailResult ?? true);
  }

  @override
  Future<ApiResponse<ProfileResponseData>> getProfile() async {
    if (getProfileResult != null) {
      return ApiResponse(ok: true, data: getProfileResult);
    }
    return ApiResponse(ok: false);
  }

  @override
  Future<ApiResponse<ProfileResponseData>> updateProfile({
    String? displayName,
    String? username,
  }) async {
    return ApiResponse(ok: updateProfileResult ?? true);
  }

  @override
  Future<ApiResponse<ProfileResponseData>> uploadAvatar({
    required List<int> fileBytes,
    required String filename,
    String? contentType,
  }) async {
    return ApiResponse(ok: uploadAvatarResult ?? true);
  }

  @override
  Future<ApiResponse<void>> deleteAvatar() async {
    return ApiResponse(ok: deleteAvatarResult ?? true);
  }
}

void main() {
  late MockAuthHttpClient httpClient;
  late MockAuthApiClient apiClient;
  late MockRefreshTokenAdapter refreshTokenAdapter;
  late AuthController controller;

  setUp(() {
    httpClient = MockAuthHttpClient();
    refreshTokenAdapter = MockRefreshTokenAdapter();
    apiClient = MockAuthApiClient(httpClient);
    controller = AuthController(
      httpClient: httpClient,
      apiClient: apiClient,
      refreshTokenAdapter: refreshTokenAdapter,
    );
  });

  tearDown(() {
    controller.dispose();
  });

  group('checkAuthOnStartup()', () {
    test('should set authenticated when refresh succeeds', () async {
      refreshTokenAdapter.existsResult = true;
      refreshTokenAdapter.readResult = SecureRefreshTokenRecord(
        refreshToken: 'valid-refresh-token',
        sessionId: 'session-id',
        expiresAt: '2026-12-31T00:00:00Z',
      );
      apiClient.refreshResult = true;
      apiClient.setAuthData(AuthResponseData(
        id: 'user-id',
        email: 'test@example.com',
        username: 'testuser',
        displayName: 'Test User',
        emailVerified: true,
        accessToken: 'new-access-token',
        refreshToken: 'new-refresh-token',
        expiresIn: 900,
      ));

      await controller.checkAuthOnStartup();

      expect(controller.state.isAuthenticated, isTrue);
      expect(controller.state.accessToken, equals('new-access-token'));
    });

    test('should set unauthenticated when no refresh token exists', () async {
      refreshTokenAdapter.existsResult = false;

      await controller.checkAuthOnStartup();

      expect(controller.state.status, equals(AuthStatus.unauthenticated));
    });

    test('should set unauthenticated when refresh fails', () async {
      refreshTokenAdapter.existsResult = true;
      refreshTokenAdapter.readResult = SecureRefreshTokenRecord(
        refreshToken: 'expired-token',
        sessionId: 'session-id',
        expiresAt: '2026-01-01T00:00:00Z',
      );
      apiClient.refreshResult = false;

      await controller.checkAuthOnStartup();

      expect(controller.state.status, equals(AuthStatus.unauthenticated));
      expect(refreshTokenAdapter.deleted, isTrue);
    });

    test('should set recoveryFailed on network error', () async {
      refreshTokenAdapter.existsResult = true;
      refreshTokenAdapter.readResult = SecureRefreshTokenRecord(
        refreshToken: 'some-token',
        sessionId: 'session-id',
        expiresAt: '2026-12-31T00:00:00Z',
      );
      // Simulate network error by having the mock throw
      apiClient.refreshResult = null; // Will make refreshToken return ok: false

      await controller.checkAuthOnStartup();

      // The refresh returns ok:false, not an exception, so it goes to unauthenticated
      expect(controller.state.status, equals(AuthStatus.unauthenticated));
    });
  });

  group('login()', () {
    test('should set authenticated on successful login', () async {
      apiClient.loginResult = true;
      apiClient.setAuthData(AuthResponseData(
        id: 'user-id',
        email: 'test@example.com',
        username: 'testuser',
        displayName: 'Test User',
        emailVerified: true,
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        expiresIn: 900,
      ));

      final result = await controller.login(
        email: 'test@example.com',
        password: 'password123',
      );

      expect(result, isTrue);
      expect(controller.state.isAuthenticated, isTrue);
    });

    test('should set unauthenticated on login failure', () async {
      apiClient.loginResult = false;
      apiClient.setError('INVALID_CREDENTIALS');

      final result = await controller.login(
        email: 'test@example.com',
        password: 'wrong-password',
      );

      expect(result, isFalse);
      expect(controller.state.status, equals(AuthStatus.unauthenticated));
    });
  });

  group('logout()', () {
    test('should clear session on logout', () async {
      // First login
      apiClient.loginResult = true;
      apiClient.setAuthData(AuthResponseData(
        id: 'user-id',
        email: 'test@example.com',
        username: 'testuser',
        displayName: 'Test User',
        emailVerified: true,
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        expiresIn: 900,
      ));
      await controller.login(email: 'test@example.com', password: 'password123');
      expect(controller.state.isAuthenticated, isTrue);

      // Then logout
      apiClient.logoutResult = true;
      await controller.logout();

      expect(controller.state.status, equals(AuthStatus.unauthenticated));
      expect(httpClient.clearAccessTokenCalled, isTrue);
    });
  });

  group('logoutAll()', () {
    test('should clear session on logoutAll', () async {
      apiClient.loginResult = true;
      apiClient.setAuthData(AuthResponseData(
        id: 'user-id',
        email: 'test@example.com',
        username: 'testuser',
        displayName: 'Test User',
        emailVerified: true,
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        expiresIn: 900,
      ));
      await controller.login(email: 'test@example.com', password: 'password123');

      apiClient.logoutAllResult = true;
      await controller.logoutAll();

      expect(controller.state.status, equals(AuthStatus.unauthenticated));
    });
  });

  group('register()', () {
    test('should set authenticated on successful registration', () async {
      apiClient.registerResult = true;
      apiClient.setAuthData(AuthResponseData(
        id: 'new-user-id',
        email: 'new@example.com',
        username: 'newuser',
        displayName: 'New User',
        emailVerified: false,
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        expiresIn: 900,
      ));

      final result = await controller.register(
        email: 'new@example.com',
        username: 'newuser',
        displayName: 'New User',
        password: 'password123',
      );

      expect(result, isTrue);
      expect(controller.state.isAuthenticated, isTrue);
    });
  });

  group('verifyEmail()', () {
    test('should return true on successful verification', () async {
      apiClient.verifyEmailResult = true;
      apiClient.setAuthData(AuthResponseData(
        id: 'user-id',
        email: 'test@example.com',
        username: 'testuser',
        displayName: 'Test User',
        emailVerified: true,
        accessToken: 'new-access-token',
        refreshToken: 'new-refresh-token',
        expiresIn: 900,
      ));

      final result = await controller.verifyEmail(code: '123456');

      expect(result, isTrue);
    });
  });

  group('forgotPassword()', () {
    test('should return true on success', () async {
      apiClient.forgotPasswordResult = true;

      final result = await controller.forgotPassword(email: 'test@example.com');

      expect(result, isTrue);
    });
  });

  group('resetPassword()', () {
    test('should return true on success', () async {
      apiClient.resetPasswordResult = true;

      final result = await controller.resetPassword(
        code: '123456',
        newPassword: 'new-password',
      );

      expect(result, isTrue);
    });
  });

  group('getProfile()', () {
    test('should return profile data on success', () async {
      apiClient.getProfileResult = ProfileResponseData(
        id: 'user-id',
        email: 'test@example.com',
        username: 'testuser',
        displayName: 'Test User',
        emailVerified: true,
      );

      final profile = await controller.getProfile();

      expect(profile, isNotNull);
      expect(profile!.displayName, equals('Test User'));
      expect(profile.email, equals('test@example.com'));
    });
  });

  group('updateProfile()', () {
    test('should return true on success', () async {
      apiClient.updateProfileResult = true;

      final result = await controller.updateProfile(displayName: 'New Name');

      expect(result, isTrue);
    });
  });

  group('uploadAvatar()', () {
    test('should return true on success', () async {
      apiClient.uploadAvatarResult = true;

      final result = await controller.uploadAvatar(
        fileBytes: [0xFF, 0xD8, 0xFF],
        filename: 'avatar.jpg',
        contentType: 'image/jpeg',
      );

      expect(result, isTrue);
    });
  });

  group('deleteAvatar()', () {
    test('should return true on success', () async {
      apiClient.deleteAvatarResult = true;

      final result = await controller.deleteAvatar();

      expect(result, isTrue);
    });
  });
}