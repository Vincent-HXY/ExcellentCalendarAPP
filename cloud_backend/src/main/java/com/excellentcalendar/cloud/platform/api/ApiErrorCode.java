package com.excellentcalendar.cloud.platform.api;

/**
 * Backend API error codes. Values and messages come from {@code contracts/error_codes.yaml}.
 */
public enum ApiErrorCode {

    API_VALIDATION_FAILED("API_VALIDATION_FAILED", "Backend API request does not match the contract", false, 400),
    API_UNAUTHENTICATED("API_UNAUTHENTICATED", "Authentication is required", false, 401),
    API_FORBIDDEN("API_FORBIDDEN", "The authenticated user is not allowed to perform this operation", false, 403),
    API_RATE_LIMITED("API_RATE_LIMITED", "Too many requests", true, 429),
    API_INTERNAL_ERROR("API_INTERNAL_ERROR", "Backend service failed to process the request", true, 500),

    AUTH_INVALID_CREDENTIALS("AUTH_INVALID_CREDENTIALS", "The email or password is incorrect", false, 401),
    AUTH_EMAIL_UNVERIFIED("AUTH_EMAIL_UNVERIFIED", "The login email has not been verified", false, 403),
    AUTH_ACCOUNT_DISABLED("AUTH_ACCOUNT_DISABLED", "The account is disabled", false, 403),
    AUTH_EMAIL_ALREADY_EXISTS("AUTH_EMAIL_ALREADY_EXISTS", "The email is already associated with an account", false, 409),
    AUTH_USERNAME_ALREADY_EXISTS("AUTH_USERNAME_ALREADY_EXISTS", "The username is already in use", false, 409),
    AUTH_VERIFICATION_INVALID("AUTH_VERIFICATION_INVALID", "The verification credential is invalid", false, 400),
    AUTH_VERIFICATION_EXPIRED("AUTH_VERIFICATION_EXPIRED", "The verification challenge has expired", false, 400),
    AUTH_VERIFICATION_USED("AUTH_VERIFICATION_USED", "The verification challenge has already been used", false, 400),
    AUTH_PASSWORD_POLICY_VIOLATION("AUTH_PASSWORD_POLICY_VIOLATION", "The password does not meet the active password policy", false, 400),
    AUTH_CURRENT_PASSWORD_INVALID("AUTH_CURRENT_PASSWORD_INVALID", "The current password is incorrect", false, 400),
    AUTH_PASSWORD_UNCHANGED("AUTH_PASSWORD_UNCHANGED", "The new password must differ from the current password", false, 400),
    AUTH_REFRESH_TOKEN_INVALID("AUTH_REFRESH_TOKEN_INVALID", "The refresh token is invalid or revoked", false, 401),
    AUTH_REFRESH_TOKEN_REUSED("AUTH_REFRESH_TOKEN_REUSED", "A consumed refresh token was reused and the session family was revoked", false, 401),
    AUTH_SESSION_EXPIRED("AUTH_SESSION_EXPIRED", "The authenticated session has expired", false, 401),

    USER_PROFILE_INVALID("USER_PROFILE_INVALID", "The user profile is invalid", false, 400),
    AVATAR_TYPE_UNSUPPORTED("AVATAR_TYPE_UNSUPPORTED", "The avatar file type is unsupported", false, 415),
    AVATAR_TOO_LARGE("AVATAR_TOO_LARGE", "The avatar file exceeds the 5 MiB limit", false, 413),
    AVATAR_UPLOAD_FAILED("AVATAR_UPLOAD_FAILED", "The avatar could not be stored or processed", true, 500);

    private final String code;
    private final String message;
    private final boolean retryable;
    private final int httpStatus;

    ApiErrorCode(String code, String message, boolean retryable, int httpStatus) {
        this.code = code;
        this.message = message;
        this.retryable = retryable;
        this.httpStatus = httpStatus;
    }

    public String code() {
        return code;
    }

    public String message() {
        return message;
    }

    public boolean retryable() {
        return retryable;
    }

    public int httpStatus() {
        return httpStatus;
    }
}
