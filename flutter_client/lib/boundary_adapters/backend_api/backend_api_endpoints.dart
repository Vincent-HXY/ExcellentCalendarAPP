/// Endpoint table mirroring contracts/backend_api.yaml (v1).
class BackendApiEndpoint {
  const BackendApiEndpoint({
    required this.method,
    required this.path,
    required this.authentication,
    this.idempotencyRequired = false,
  });

  final String method;
  final String path;

  /// 'public' | 'bearer' | 'refresh_token'
  final String authentication;
  final bool idempotencyRequired;

  bool get requiresAuth => authentication == 'bearer';
}

class BackendApiEndpoints {
  const BackendApiEndpoints._();

  static const register = BackendApiEndpoint(
    method: 'POST',
    path: '/auth/register',
    authentication: 'public',
    idempotencyRequired: true,
  );
  static const registrationVerify = BackendApiEndpoint(
    method: 'POST',
    path: '/auth/registration/verify',
    authentication: 'public',
  );
  static const registrationResend = BackendApiEndpoint(
    method: 'POST',
    path: '/auth/registration/resend',
    authentication: 'public',
    idempotencyRequired: true,
  );
  static const login = BackendApiEndpoint(
    method: 'POST',
    path: '/auth/login',
    authentication: 'public',
  );
  static const tokenRefresh = BackendApiEndpoint(
    method: 'POST',
    path: '/auth/token/refresh',
    authentication: 'refresh_token',
  );
  static const logout = BackendApiEndpoint(
    method: 'POST',
    path: '/auth/logout',
    authentication: 'refresh_token',
  );
  static const logoutAll = BackendApiEndpoint(
    method: 'POST',
    path: '/auth/logout-all',
    authentication: 'bearer',
  );
  static const passwordResetRequest = BackendApiEndpoint(
    method: 'POST',
    path: '/auth/password-reset/request',
    authentication: 'public',
    idempotencyRequired: true,
  );
  static const passwordResetConfirm = BackendApiEndpoint(
    method: 'POST',
    path: '/auth/password-reset/confirm',
    authentication: 'public',
  );
  static const passwordChange = BackendApiEndpoint(
    method: 'POST',
    path: '/auth/password/change',
    authentication: 'bearer',
  );
  static const emailChangeRequest = BackendApiEndpoint(
    method: 'POST',
    path: '/auth/email-change/request',
    authentication: 'bearer',
    idempotencyRequired: true,
  );
  static const emailChangeConfirm = BackendApiEndpoint(
    method: 'POST',
    path: '/auth/email-change/confirm',
    authentication: 'bearer',
  );
  static const userGetCurrent = BackendApiEndpoint(
    method: 'GET',
    path: '/users/me',
    authentication: 'bearer',
  );
  static const userUpdateCurrent = BackendApiEndpoint(
    method: 'PATCH',
    path: '/users/me',
    authentication: 'bearer',
  );
  static const avatarDelete = BackendApiEndpoint(
    method: 'DELETE',
    path: '/users/me/avatar',
    authentication: 'bearer',
  );
}
