package com.excellentcalendar.cloud.platform.security;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * JWT signing and claim configuration. The secret is Base64 encoded and must decode to at
 * least 32 bytes for HS256; the api profile fails fast when it is missing or too short.
 */
@ConfigurationProperties("excellent-calendar.security.jwt")
public class JwtProperties {

    private String secret;
    private String issuer = "https://excellent-calendar.local/cloud";
    private String audience = "excellent-calendar-android";
    private long accessTokenTtlSeconds = 900;

    public String getSecret() {
        return secret;
    }

    public void setSecret(String secret) {
        this.secret = secret;
    }

    public String getIssuer() {
        return issuer;
    }

    public void setIssuer(String issuer) {
        this.issuer = issuer;
    }

    public String getAudience() {
        return audience;
    }

    public void setAudience(String audience) {
        this.audience = audience;
    }

    public long getAccessTokenTtlSeconds() {
        return accessTokenTtlSeconds;
    }

    public void setAccessTokenTtlSeconds(long accessTokenTtlSeconds) {
        this.accessTokenTtlSeconds = accessTokenTtlSeconds;
    }
}
