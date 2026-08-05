import 'package:flutter/foundation.dart';

import 'auth_api_client.dart';
import 'auth_http_client.dart';
import 'auth_refresh_token_adapter.dart';
import 'auth_state.dart';

/// Global authentication state manager.
///
/// Must be provided at the app root and passed down to pages.
/// Uses [ChangeNotifier] to notify listeners of state changes.
class AuthController extends ChangeNotifier {
  AuthController({
    required AuthHttpClient httpClient,
    required AuthApiClient apiClient,
    required AuthRefreshTokenAdapter refreshTokenAdapter,
  })  : _httpClient = httpClient,
        _apiClient = apiClient,
        _refreshTokenAdapter = refreshTokenAdapter;

  final AuthHttpClient _httpClient;
  final AuthApiClient _apiClient;
  final AuthRefreshTokenAdapter _refreshTokenAdapter;

  AuthState _state = const AuthState();
  bool _disposed = false;

  AuthState get state => _state;

  /// The current Access Token, or null if not authenticated.
  String? _accessToken;
  String? _userId;
  String? _email;

  // ---------------------------------------------------------------
  // App startup auth check
  // ---------------------------------------------------------------

  /// Run the startup auth check:
  /// 1. Check if a Refresh Token exists in Android secure storage
  /// 2. If yes, try to refresh the session
  /// 3. On success, enter authenticated state
  /// 4. On failure, enter unauthenticated state
  Future<void> checkAuthOnStartup() async {
    _updateState(const AuthState(status: AuthStatus.checking));

    try {
      final presence = await _refreshTokenAdapter.exists();
      if (!presence.result.ok || !presence.result.data!.exists) {
        _updateState(const AuthState(status: AuthStatus.unauthenticated));
        return;
      }

      _updateState(const AuthState(status: AuthStatus.refreshing));

      // Read the Refresh Token from Android secure storage
      final readResult = await _refreshTokenAdapter.read();
      if (!readResult.result.ok || readResult.result.data == null) {
        await _refreshTokenAdapter.delete();
        _updateState(const AuthState(status: AuthStatus.unauthenticated));
        return;
      }

      final record = readResult.result.data!;

      // Try to refresh the session
      final refreshResponse = await _apiClient.refreshToken(
        refreshToken: record.refreshToken,
      );

      if (refreshResponse.ok && refreshResponse.data != null) {
        final authData = refreshResponse.data!;

        // Store new Access Token in memory
        _accessToken = authData.accessToken;
        _userId = authData.id;
        _email = authData.email;
        _httpClient.setAccessToken(authData.accessToken);

        // Store new Refresh Token in Android secure storage
        await _refreshTokenAdapter.store(
          refreshToken: authData.refreshToken,
          sessionId: authData.id,
          expiresAt: _computeExpiresAt(authData.expiresIn),
        );

        _updateState(AuthState(
          status: AuthStatus.authenticated,
          accessToken: authData.accessToken,
          userId: authData.id,
          email: authData.email,
        ));
      } else {
        // Refresh failed — delete the stored Refresh Token
        await _refreshTokenAdapter.delete();
        _updateState(const AuthState(status: AuthStatus.unauthenticated));
      }
    } catch (_) {
      // Network error
      _updateState(const AuthState(
        status: AuthStatus.recoveryFailed,
        errorMessage: 'Unable to check login status. Please check your network.',
      ));
    }
  }

  // ---------------------------------------------------------------
  // Register
  // ---------------------------------------------------------------

  /// Attempt to register a new account.
  Future<bool> register({
    required String email,
    required String username,
    required String displayName,
    required String password,
  }) async {
    _updateState(const AuthState(status: AuthStatus.refreshing));

    try {
      final response = await _apiClient.register(
        email: email,
        username: username,
        displayName: displayName,
        password: password,
      );

      if (response.ok && response.data != null) {
        final authData = response.data!;
        _accessToken = authData.accessToken;
        _userId = authData.id;
        _email = authData.email;

        _httpClient.setAccessToken(authData.accessToken);

        await _refreshTokenAdapter.store(
          refreshToken: authData.refreshToken,
          sessionId: authData.id,
          expiresAt: _computeExpiresAt(authData.expiresIn),
        );

        _updateState(AuthState(
          status: AuthStatus.authenticated,
          accessToken: authData.accessToken,
          userId: authData.id,
          email: authData.email,
        ));
        return true;
      } else {
        _updateState(AuthState(
          status: AuthStatus.unauthenticated,
          errorMessage: _extractError(response.error?.message),
        ));
        return false;
      }
    } catch (_) {
      _updateState(const AuthState(
        status: AuthStatus.unauthenticated,
        errorMessage: '网络错误，请检查网络连接后重试',
      ));
      return false;
    }
  }

  // ---------------------------------------------------------------
  // Login
  // ---------------------------------------------------------------

  /// Attempt to log in with email and password.
  Future<bool> login({required String email, required String password}) async {
    _updateState(const AuthState(status: AuthStatus.refreshing));

    try {
      final response = await _apiClient.login(email: email, password: password);

      if (response.ok && response.data != null) {
        final authData = response.data!;
        _accessToken = authData.accessToken;
        _userId = authData.id;
        _email = authData.email;

        _httpClient.setAccessToken(authData.accessToken);

        await _refreshTokenAdapter.store(
          refreshToken: authData.refreshToken,
          sessionId: authData.id,
          expiresAt: _computeExpiresAt(authData.expiresIn),
        );

        _updateState(AuthState(
          status: AuthStatus.authenticated,
          accessToken: authData.accessToken,
          userId: authData.id,
          email: authData.email,
        ));
        return true;
      } else {
        _updateState(AuthState(
          status: AuthStatus.unauthenticated,
          errorMessage: response.error?.message ?? 'Login failed',
        ));
        return false;
      }
    } catch (_) {
      _updateState(const AuthState(
        status: AuthStatus.unauthenticated,
        errorMessage: '网络错误，请检查网络连接后重试',
      ));
      return false;
    }
  }

  // ---------------------------------------------------------------
  // Logout
  // ---------------------------------------------------------------

  /// Log out the current user.
  Future<void> logout() async {
    final readResult = await _refreshTokenAdapter.read();
    if (readResult.result.ok && readResult.result.data != null) {
      await _apiClient.logout(refreshToken: readResult.result.data!.refreshToken);
    }

    await _clearSession();
  }

  /// Log out from all devices.
  Future<void> logoutAll() async {
    await _apiClient.logoutAll();
    await _clearSession();
  }

  // ---------------------------------------------------------------
  // Email verification
  // ---------------------------------------------------------------

  /// Verify email with the 6-digit code.
  Future<bool> verifyEmail({required String code}) async {
    try {
      final response = await _apiClient.verifyEmail(code: code);
      if (response.ok && response.data != null) {
        final authData = response.data!;
        _accessToken = authData.accessToken;
        _httpClient.setAccessToken(authData.accessToken);

        await _refreshTokenAdapter.store(
          refreshToken: authData.refreshToken,
          sessionId: authData.id,
          expiresAt: _computeExpiresAt(authData.expiresIn),
        );

        _updateState(AuthState(
          status: AuthStatus.authenticated,
          accessToken: authData.accessToken,
          userId: authData.id,
          email: authData.email,
        ));
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Resend the email verification code.
  Future<bool> resendVerificationCode() async {
    try {
      final response = await _apiClient.resendVerificationCode();
      return response.ok;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------
  // Password reset
  // ---------------------------------------------------------------

  /// Request a password reset email.
  Future<bool> forgotPassword({required String email}) async {
    try {
      final response = await _apiClient.forgotPassword(email: email);
      return response.ok;
    } catch (_) {
      return false;
    }
  }

  /// Reset the password with verification code and new password.
  Future<bool> resetPassword({
    required String code,
    required String newPassword,
  }) async {
    try {
      final response = await _apiClient.resetPassword(
        code: code,
        newPassword: newPassword,
      );
      return response.ok;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------
  // Change password (authenticated)
  // ---------------------------------------------------------------

  /// Change the current user's password.
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final response = await _apiClient.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      if (response.ok && response.data != null) {
        final authData = response.data!;
        _accessToken = authData.accessToken;
        _httpClient.setAccessToken(authData.accessToken);

        await _refreshTokenAdapter.store(
          refreshToken: authData.refreshToken,
          sessionId: authData.id,
          expiresAt: _computeExpiresAt(authData.expiresIn),
        );
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------
  // Change email (authenticated)
  // ---------------------------------------------------------------

  /// Request an email change.
  Future<bool> changeEmail({
    required String newEmail,
    required String currentPassword,
  }) async {
    try {
      final response = await _apiClient.changeEmail(
        newEmail: newEmail,
        currentPassword: currentPassword,
      );
      return response.ok;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------

  /// Get the current user's profile.
  Future<ProfileResponseData?> getProfile() async {
    try {
      final response = await _apiClient.getProfile();
      if (response.ok && response.data != null) {
        return response.data;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Update the current user's profile (display name, username).
  Future<bool> updateProfile({
    String? displayName,
    String? username,
  }) async {
    try {
      final response = await _apiClient.updateProfile(
        displayName: displayName,
        username: username,
      );
      return response.ok;
    } catch (_) {
      return false;
    }
  }

  /// Upload a new avatar.
  Future<bool> uploadAvatar({
    required List<int> fileBytes,
    required String filename,
    String? contentType,
  }) async {
    try {
      final response = await _apiClient.uploadAvatar(
        fileBytes: fileBytes,
        filename: filename,
        contentType: contentType,
      );
      return response.ok;
    } catch (_) {
      return false;
    }
  }

  /// Delete the current avatar.
  Future<bool> deleteAvatar() async {
    try {
      final response = await _apiClient.deleteAvatar();
      return response.ok;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------

  Future<void> _clearSession() async {
    _accessToken = null;
    _userId = null;
    _email = null;
    _httpClient.clearAccessToken();

    await _refreshTokenAdapter.delete();

    _updateState(const AuthState(status: AuthStatus.unauthenticated));
  }

  void _updateState(AuthState newState) {
    _state = newState;
    _notifyListeners();
  }

  void _notifyListeners() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  String _computeExpiresAt(int expiresInSeconds) {
    final expiresAt =
        DateTime.now().toUtc().add(Duration(seconds: expiresInSeconds));
    return expiresAt.toIso8601String();
  }

  String? _extractError(String? message) {
    if (message == null) return null;
    if (message.contains('EMAIL_ALREADY_EXISTS')) return '该邮箱已被注册';
    if (message.contains('USERNAME_ALREADY_TAKEN')) return '该用户名已被使用';
    if (message.contains('INVALID_PASSWORD')) return '密码不符合安全要求';
    if (message.contains('RATE_LIMITED')) return '请求过于频繁，请稍后重试';
    return message;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}