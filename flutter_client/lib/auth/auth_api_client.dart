import 'auth_http_client.dart';

/// Flat auth response from the backend's [AuthResponse] DTO.
class AuthResponseData {
  const AuthResponseData({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.language,
    this.timezone,
    required this.emailVerified,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  factory AuthResponseData.fromJson(Map<String, dynamic> json) {
    return AuthResponseData(
      id: (json['userId'] ?? json['id']) as String,
      email: json['email'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      language: json['language'] as String?,
      timezone: json['timezone'] as String?,
      emailVerified: json['emailVerified'] as bool? ?? false,
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      expiresIn: json['expiresIn'] as int? ?? 900,
    );
  }

  final String id;
  final String email;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? language;
  final String? timezone;
  final bool emailVerified;
  final String accessToken;
  final String refreshToken;
  final int expiresIn;
}

/// Profile response from the backend's [ProfileResponse] DTO.
class ProfileResponseData {
  const ProfileResponseData({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.language,
    this.timezone,
    required this.emailVerified,
  });

  factory ProfileResponseData.fromJson(Map<String, dynamic> json) {
    return ProfileResponseData(
      id: (json['userId'] ?? json['id']) as String,
      email: json['email'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      language: json['language'] as String?,
      timezone: json['timezone'] as String?,
      emailVerified: json['emailVerified'] as bool? ?? false,
    );
  }

  final String id;
  final String email;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? language;
  final String? timezone;
  final bool emailVerified;
}

/// Message response from the backend's [MessageResponse] DTO.
class MessageResponseData {
  const MessageResponseData({required this.message});

  factory MessageResponseData.fromJson(Map<String, dynamic> json) {
    return MessageResponseData(message: json['message'] as String? ?? '');
  }

  final String message;
}

/// Client for backend auth API endpoints.
class AuthApiClient {
  AuthApiClient(this._httpClient);

  final AuthHttpClient _httpClient;

  /// POST /api/v1/auth/signup
  Future<ApiResponse<AuthResponseData>> register({
    required String email,
    required String username,
    required String displayName,
    required String password,
  }) async {
    return _httpClient.post(
      '/auth/signup',
      body: {
        'email': email,
        'username': username,
        'displayName': displayName,
        'password': password,
      },
      parseData: (json) => AuthResponseData.fromJson(json),
    );
  }

  /// POST /api/v1/auth/login
  Future<ApiResponse<AuthResponseData>> login({
    required String email,
    required String password,
  }) async {
    return _httpClient.post(
      '/auth/login',
      body: {'email': email, 'password': password},
      parseData: (json) => AuthResponseData.fromJson(json),
    );
  }

  /// POST /api/v1/auth/refresh
  Future<ApiResponse<AuthResponseData>> refreshToken({
    required String refreshToken,
  }) async {
    return _httpClient.post(
      '/auth/refresh',
      body: {'refreshToken': refreshToken},
      parseData: (json) => AuthResponseData.fromJson(json),
    );
  }

  /// POST /api/v1/auth/logout
  Future<ApiResponse<void>> logout({
    required String refreshToken,
  }) async {
    return _httpClient.post(
      '/auth/logout',
      body: {'refreshToken': refreshToken},
    );
  }

  /// POST /api/v1/auth/logout-all
  Future<ApiResponse<void>> logoutAll() async {
    return _httpClient.post('/auth/logout-all');
  }

  /// POST /api/v1/auth/verify-email
  Future<ApiResponse<AuthResponseData>> verifyEmail({
    required String code,
  }) async {
    return _httpClient.post(
      '/auth/verify-email',
      body: {'code': code},
      parseData: (json) => AuthResponseData.fromJson(json),
    );
  }

  /// POST /api/v1/auth/resend-verification
  Future<ApiResponse<void>> resendVerificationCode() async {
    return _httpClient.post('/auth/resend-verification');
  }

  /// POST /api/v1/auth/forgot-password
  Future<ApiResponse<void>> forgotPassword({
    required String email,
  }) async {
    return _httpClient.post(
      '/auth/forgot-password',
      body: {'email': email},
    );
  }

  /// POST /api/v1/auth/reset-password
  Future<ApiResponse<void>> resetPassword({
    required String code,
    required String newPassword,
  }) async {
    return _httpClient.post(
      '/auth/reset-password',
      body: {'code': code, 'newPassword': newPassword},
    );
  }

  /// POST /api/v1/auth/change-password
  Future<ApiResponse<AuthResponseData>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    return _httpClient.post(
      '/auth/change-password',
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
      parseData: (json) => AuthResponseData.fromJson(json),
    );
  }

  /// POST /api/v1/auth/change-email
  Future<ApiResponse<void>> changeEmail({
    required String newEmail,
    required String currentPassword,
  }) async {
    return _httpClient.post(
      '/auth/change-email',
      body: {'newEmail': newEmail, 'currentPassword': currentPassword},
    );
  }

  /// GET /api/v1/profile
  Future<ApiResponse<ProfileResponseData>> getProfile() async {
    return _httpClient.get(
      '/profile',
      parseData: (json) => ProfileResponseData.fromJson(json),
    );
  }

  /// PATCH /api/v1/profile
  Future<ApiResponse<ProfileResponseData>> updateProfile({
    String? displayName,
    String? username,
  }) async {
    final body = <String, dynamic>{};
    if (displayName != null) body['displayName'] = displayName;
    if (username != null) body['username'] = username;
    return _httpClient.patch(
      '/profile',
      body: body,
      parseData: (json) => ProfileResponseData.fromJson(json),
    );
  }

  /// POST /api/v1/users/me/avatar (multipart upload)
  Future<ApiResponse<ProfileResponseData>> uploadAvatar({
    required List<int> fileBytes,
    required String filename,
    String? contentType,
  }) async {
    return _httpClient.postMultipart(
      '/users/me/avatar',
      field: 'avatar',
      fileBytes: fileBytes,
      filename: filename,
      contentType: contentType,
      parseData: (json) => ProfileResponseData.fromJson(json),
    );
  }

  /// DELETE /api/v1/users/me/avatar
  Future<ApiResponse<void>> deleteAvatar() async {
    return _httpClient.delete('/users/me/avatar');
  }
}