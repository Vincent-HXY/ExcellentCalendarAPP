package com.excellentcalendar.cloud.platform.security;

import java.time.Clock;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.BadJwtException;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtException;

/**
 * Verifies access-token signature, expiry, issuer and audience. Throws {@link JwtException}
 * when any check fails; callers map that to API_UNAUTHENTICATED.
 */
public class AccessTokenVerifier {

    private final JwtDecoder decoder;
    private final JwtProperties properties;
    private final Clock clock;

    public AccessTokenVerifier(JwtDecoder decoder, JwtProperties properties, Clock clock) {
        this.decoder = decoder;
        this.properties = properties;
        this.clock = clock;
    }

    public Jwt verify(String token) {
        Jwt jwt = decoder.decode(token);
        OAuth2TokenValidatorResult issuerResult = checkIssuer(jwt);
        if (issuerResult.hasErrors()) {
            throw new BadJwtException("invalid issuer");
        }
        OAuth2TokenValidatorResult audienceResult = checkAudience(jwt);
        if (audienceResult.hasErrors()) {
            throw new BadJwtException("invalid audience");
        }
        if (jwt.getExpiresAt() == null || !jwt.getExpiresAt().isAfter(clock.instant())) {
            throw new BadJwtException("expired token");
        }
        return jwt;
    }

    private OAuth2TokenValidatorResult checkIssuer(Jwt jwt) {
        // Read the raw claim: Jwt.getIssuer() coerces to URL and fails on non-URL issuers.
        String issuer = jwt.getClaimAsString("iss");
        if (issuer == null || !properties.getIssuer().equals(issuer)) {
            return OAuth2TokenValidatorResult.failure();
        }
        return OAuth2TokenValidatorResult.success();
    }

    private OAuth2TokenValidatorResult checkAudience(Jwt jwt) {
        if (jwt.getAudience() == null || !jwt.getAudience().contains(properties.getAudience())) {
            return OAuth2TokenValidatorResult.failure();
        }
        return OAuth2TokenValidatorResult.success();
    }
}
