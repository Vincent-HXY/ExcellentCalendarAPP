package com.excellentcalendar.cloud.identity.infrastructure;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Identity challenge and token parameters; defaults mirror
 * {@code contracts/backend_api.yaml} security_defaults.
 */
@ConfigurationProperties("excellent-calendar.identity.challenge")
public class IdentityProperties {

    private long registrationTtlSeconds = 600;
    private long passwordResetTtlSeconds = 900;
    private long resendIntervalSeconds = 60;
    private int maxAttempts = 5;
    private long refreshTokenTtlSeconds = 2592000;

    public long getRegistrationTtlSeconds() {
        return registrationTtlSeconds;
    }

    public void setRegistrationTtlSeconds(long registrationTtlSeconds) {
        this.registrationTtlSeconds = registrationTtlSeconds;
    }

    public long getPasswordResetTtlSeconds() {
        return passwordResetTtlSeconds;
    }

    public void setPasswordResetTtlSeconds(long passwordResetTtlSeconds) {
        this.passwordResetTtlSeconds = passwordResetTtlSeconds;
    }

    public long getResendIntervalSeconds() {
        return resendIntervalSeconds;
    }

    public void setResendIntervalSeconds(long resendIntervalSeconds) {
        this.resendIntervalSeconds = resendIntervalSeconds;
    }

    public int getMaxAttempts() {
        return maxAttempts;
    }

    public void setMaxAttempts(int maxAttempts) {
        this.maxAttempts = maxAttempts;
    }

    public long getRefreshTokenTtlSeconds() {
        return refreshTokenTtlSeconds;
    }

    public void setRefreshTokenTtlSeconds(long refreshTokenTtlSeconds) {
        this.refreshTokenTtlSeconds = refreshTokenTtlSeconds;
    }
}
