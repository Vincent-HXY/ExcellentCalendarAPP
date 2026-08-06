package com.excellentcalendar.cloud.platform.jwt;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

/**
 * JWT configuration properties.
 * In production, replace the placeholder secret with a properly managed key.
 */
@Validated
@ConfigurationProperties("excellent-calendar.security.jwt")
public class JwtProperties {

    /** Temporary HMAC secret for development. Must be at least 256 bits. */
    private String secret = "temporary-dev-secret-that-is-at-least-256-bits-long-for-hmac-sha256!!";

    /** Access token TTL. Default: 15 minutes. */
    private Duration accessTokenTtl = Duration.ofSeconds(900);

    public String getSecret() { return secret; }
    public void setSecret(String secret) { this.secret = secret; }

    public Duration getAccessTokenTtl() { return accessTokenTtl; }
    public void setAccessTokenTtl(Duration accessTokenTtl) { this.accessTokenTtl = accessTokenTtl; }
}