/// Backend API v1 error codes declared in contracts/error_codes.yaml and
/// bounded by common/api_error.schema.json.
class ApiErrorCodes {
  const ApiErrorCodes._();

  static const apiValidationFailed = 'API_VALIDATION_FAILED';
  static const apiUnauthenticated = 'API_UNAUTHENTICATED';
  static const apiForbidden = 'API_FORBIDDEN';
  static const apiRateLimited = 'API_RATE_LIMITED';
  static const apiInternalError = 'API_INTERNAL_ERROR';
  static const authInvalidCredentials = 'AUTH_INVALID_CREDENTIALS';
  static const authEmailUnverified = 'AUTH_EMAIL_UNVERIFIED';
  static const authAccountDisabled = 'AUTH_ACCOUNT_DISABLED';
  static const authEmailAlreadyExists = 'AUTH_EMAIL_ALREADY_EXISTS';
  static const authUsernameAlreadyExists = 'AUTH_USERNAME_ALREADY_EXISTS';
  static const authVerificationInvalid = 'AUTH_VERIFICATION_INVALID';
  static const authVerificationExpired = 'AUTH_VERIFICATION_EXPIRED';
  static const authVerificationUsed = 'AUTH_VERIFICATION_USED';
  static const authPasswordPolicyViolation = 'AUTH_PASSWORD_POLICY_VIOLATION';
  static const authCurrentPasswordInvalid = 'AUTH_CURRENT_PASSWORD_INVALID';
  static const authPasswordUnchanged = 'AUTH_PASSWORD_UNCHANGED';
  static const authRefreshTokenInvalid = 'AUTH_REFRESH_TOKEN_INVALID';
  static const authRefreshTokenReused = 'AUTH_REFRESH_TOKEN_REUSED';
  static const authSessionExpired = 'AUTH_SESSION_EXPIRED';
  static const userProfileInvalid = 'USER_PROFILE_INVALID';
  static const avatarTypeUnsupported = 'AVATAR_TYPE_UNSUPPORTED';
  static const avatarTooLarge = 'AVATAR_TOO_LARGE';
  static const avatarUploadFailed = 'AVATAR_UPLOAD_FAILED';

  static const values = {
    apiValidationFailed,
    apiUnauthenticated,
    apiForbidden,
    apiRateLimited,
    apiInternalError,
    authInvalidCredentials,
    authEmailUnverified,
    authAccountDisabled,
    authEmailAlreadyExists,
    authUsernameAlreadyExists,
    authVerificationInvalid,
    authVerificationExpired,
    authVerificationUsed,
    authPasswordPolicyViolation,
    authCurrentPasswordInvalid,
    authPasswordUnchanged,
    authRefreshTokenInvalid,
    authRefreshTokenReused,
    authSessionExpired,
    userProfileInvalid,
    avatarTypeUnsupported,
    avatarTooLarge,
    avatarUploadFailed,
  };

  /// Codes that mean the current Access Token is no longer valid and a
  /// single-flight refresh should be attempted.
  static bool isAccessTokenFailure(String code) =>
      code == apiUnauthenticated || code == authSessionExpired;

  /// Codes that mean the Refresh Token itself can no longer be used.
  static bool isRefreshTokenFailure(String code) =>
      code == authRefreshTokenInvalid ||
      code == authRefreshTokenReused ||
      code == authSessionExpired ||
      code == authAccountDisabled;
}
