package com.excellentcalendar.cloud.platform.password;

import com.excellentcalendar.cloud.platform.api.ApiException;
import org.springframework.http.HttpStatus;

/**
 * Auth-specific security exceptions with the correct error codes.
 */
public final class AuthErrors {

    private AuthErrors() {}

    public static ApiException invalidCredentials() {
        return new ApiException("AUTH_INVALID_CREDENTIALS",
                "The email or password is incorrect", false, HttpStatus.UNAUTHORIZED);
    }

    public static ApiException emailUnverified() {
        return new ApiException("AUTH_EMAIL_UNVERIFIED",
                "The login email has not been verified", false, HttpStatus.FORBIDDEN);
    }

    public static ApiException accountDisabled() {
        return new ApiException("AUTH_ACCOUNT_DISABLED",
                "The account is disabled", false, HttpStatus.FORBIDDEN);
    }

    public static ApiException emailAlreadyExists() {
        return new ApiException("AUTH_EMAIL_ALREADY_EXISTS",
                "The email is already associated with an account", false, HttpStatus.CONFLICT);
    }

    public static ApiException usernameAlreadyExists() {
        return new ApiException("AUTH_USERNAME_ALREADY_EXISTS",
                "The username is already in use", false, HttpStatus.CONFLICT);
    }

    public static ApiException verificationInvalid() {
        return new ApiException("AUTH_VERIFICATION_INVALID",
                "The verification credential is invalid", false, HttpStatus.BAD_REQUEST);
    }

    public static ApiException verificationExpired() {
        return new ApiException("AUTH_VERIFICATION_EXPIRED",
                "The verification challenge has expired", false, HttpStatus.GONE);
    }

    public static ApiException verificationUsed() {
        return new ApiException("AUTH_VERIFICATION_USED",
                "The verification challenge has already been used", false, HttpStatus.GONE);
    }

    public static ApiException passwordPolicyViolation() {
        return new ApiException("AUTH_PASSWORD_POLICY_VIOLATION",
                "The password does not meet the active password policy", false, HttpStatus.BAD_REQUEST);
    }

    public static ApiException currentPasswordInvalid() {
        return new ApiException("AUTH_CURRENT_PASSWORD_INVALID",
                "The current password is incorrect", false, HttpStatus.UNAUTHORIZED);
    }

    public static ApiException passwordUnchanged() {
        return new ApiException("AUTH_PASSWORD_UNCHANGED",
                "The new password must differ from the current password", false, HttpStatus.BAD_REQUEST);
    }

    public static ApiException refreshTokenInvalid() {
        return new ApiException("AUTH_REFRESH_TOKEN_INVALID",
                "The refresh token is invalid or revoked", false, HttpStatus.UNAUTHORIZED);
    }

    public static ApiException refreshTokenReused() {
        return new ApiException("AUTH_REFRESH_TOKEN_REUSED",
                "A consumed refresh token was reused and the session family was revoked",
                false, HttpStatus.UNAUTHORIZED);
    }

    public static ApiException sessionExpired() {
        return new ApiException("AUTH_SESSION_EXPIRED",
                "The authenticated session has expired", false, HttpStatus.UNAUTHORIZED);
    }
}