package com.excellentcalendar.cloud.platform.jwt;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jws;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import java.time.Clock;
import java.time.Instant;
import java.util.Date;
import java.util.UUID;
import javax.crypto.SecretKey;

/**
 * Service for creating and verifying JWT access tokens.
 * Uses HMAC-SHA256 with a configurable secret.
 * <p>
 * Never log the tokens or the secret.
 */
public class JwtTokenService {

    private final SecretKey key;
    private final long accessTokenTtlSeconds;
    private final Clock clock;

    JwtTokenService(JwtProperties properties) {
        this(properties, Clock.systemUTC());
    }

    JwtTokenService(JwtProperties properties, Clock clock) {
        this.key = Keys.hmacShaKeyFor(properties.getSecret().getBytes());
        this.accessTokenTtlSeconds = properties.getAccessTokenTtl().toSeconds();
        this.clock = clock;
    }

    /**
     * Creates a signed JWT access token for the given user.
     *
     * @param userId the authenticated user's UUID
     * @param sessionId the current session UUID
     * @return the signed JWT string (min 32 chars)
     */
    public String createAccessToken(UUID userId, UUID sessionId) {
        Instant now = clock.instant();
        return Jwts.builder()
                .subject(userId.toString())
                .claim("sid", sessionId.toString())
                .issuedAt(Date.from(now))
                .expiration(Date.from(now.plusSeconds(accessTokenTtlSeconds)))
                .signWith(key)
                .compact();
    }

    /**
     * Parses and validates a JWT access token.
     *
     * @param token the raw JWT string
     * @return the parsed claims, or null if the token is invalid/expired
     */
    public ParsedToken parseAccessToken(String token) {
        try {
            Jws<Claims> jws = Jwts.parser()
                    .verifyWith(key)
                    .build()
                    .parseSignedClaims(token);
            Claims claims = jws.getPayload();
            return new ParsedToken(
                    UUID.fromString(claims.getSubject()),
                    UUID.fromString(claims.get("sid", String.class)),
                    claims.getExpiration().toInstant());
        } catch (JwtException | IllegalArgumentException e) {
            return null;
        }
    }

    /**
     * Result of parsing a JWT access token.
     */
    public record ParsedToken(
            UUID userId,
            UUID sessionId,
            Instant expiresAt
    ) {
        public boolean isExpired(Clock clock) {
            return expiresAt.isBefore(clock.instant());
        }
    }
}