package com.excellentcalendar.cloud.identity.config;

import java.time.Duration;
import javax.crypto.SecretKey;
import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties("excellent-calendar.identity")
public class IdentityProperties {

    /**
     * Secret key for signing JWTs. Must be at least 256 bits for HS256.
     * In production, inject via environment variable EXCELLENT_CALENDAR_IDENTITY_JWT_SECRET.
     */
    private String jwtSecret;

    /**
     * Access Token expiration duration.
     */
    private Duration accessTokenExpiration = Duration.ofMinutes(15);

    /**
     * Refresh Token expiration duration.
     */
    private Duration refreshTokenExpiration = Duration.ofDays(30);

    /**
     * Email verification code expiration duration.
     */
    private Duration verificationCodeExpiration = Duration.ofMinutes(15);

    /**
     * Password reset token expiration duration.
     */
    private Duration passwordResetExpiration = Duration.ofMinutes(30);

    /**
     * Email change request expiration duration.
     */
    private Duration emailChangeExpiration = Duration.ofMinutes(15);

    /**
     * Rate limit: max verification code requests per time window.
     */
    private int verificationCodeMaxPerWindow = 3;

    /**
     * Rate limit: verification code time window duration.
     */
    private Duration verificationCodeWindow = Duration.ofMinutes(10);

    /**
     * Base URL for the application (used in email links).
     */
    private String appBaseUrl = "http://localhost:8080";

    /**
     * From address for outgoing emails.
     */
    private String mailFrom = "noreply@excellentcalendar.app";

    public String getJwtSecret() {
        return jwtSecret;
    }

    public void setJwtSecret(String jwtSecret) {
        this.jwtSecret = jwtSecret;
    }

    public Duration getAccessTokenExpiration() {
        return accessTokenExpiration;
    }

    public void setAccessTokenExpiration(Duration accessTokenExpiration) {
        this.accessTokenExpiration = accessTokenExpiration;
    }

    public Duration getRefreshTokenExpiration() {
        return refreshTokenExpiration;
    }

    public void setRefreshTokenExpiration(Duration refreshTokenExpiration) {
        this.refreshTokenExpiration = refreshTokenExpiration;
    }

    public Duration getVerificationCodeExpiration() {
        return verificationCodeExpiration;
    }

    public void setVerificationCodeExpiration(Duration verificationCodeExpiration) {
        this.verificationCodeExpiration = verificationCodeExpiration;
    }

    public Duration getPasswordResetExpiration() {
        return passwordResetExpiration;
    }

    public void setPasswordResetExpiration(Duration passwordResetExpiration) {
        this.passwordResetExpiration = passwordResetExpiration;
    }

    public Duration getEmailChangeExpiration() {
        return emailChangeExpiration;
    }

    public void setEmailChangeExpiration(Duration emailChangeExpiration) {
        this.emailChangeExpiration = emailChangeExpiration;
    }

    public int getVerificationCodeMaxPerWindow() {
        return verificationCodeMaxPerWindow;
    }

    public void setVerificationCodeMaxPerWindow(int verificationCodeMaxPerWindow) {
        this.verificationCodeMaxPerWindow = verificationCodeMaxPerWindow;
    }

    public Duration getVerificationCodeWindow() {
        return verificationCodeWindow;
    }

    public void setVerificationCodeWindow(Duration verificationCodeWindow) {
        this.verificationCodeWindow = verificationCodeWindow;
    }

    public String getAppBaseUrl() {
        return appBaseUrl;
    }

    public void setAppBaseUrl(String appBaseUrl) {
        this.appBaseUrl = appBaseUrl;
    }

    public String getMailFrom() {
        return mailFrom;
    }

    public void setMailFrom(String mailFrom) {
        this.mailFrom = mailFrom;
    }

    public SecretKey jwtSecretKey() {
        if (jwtSecret == null || jwtSecret.isBlank()) {
            throw new IllegalStateException(
                    "JWT secret is not configured. Set excellent-calendar.identity.jwt-secret or "
                            + "EXCELLENT_CALENDAR_IDENTITY_JWT_SECRET environment variable");
        }
        byte[] keyBytes = jwtSecret.getBytes(java.nio.charset.StandardCharsets.UTF_8);
        if (keyBytes.length < 32) {
            throw new IllegalArgumentException("JWT secret must be at least 256 bits (32 characters)");
        }
        return new javax.crypto.spec.SecretKeySpec(keyBytes, "HmacSHA256");
    }
}