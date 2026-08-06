package com.excellentcalendar.cloud.identity.application;

import java.time.Instant;
import java.util.UUID;

/**
 * Result of a successful authentication operation.
 */
public record AuthenticationResult(
        UUID userId,
        String email,
        String username,
        String displayName,
        String accessToken,
        Instant accessTokenExpiresAt,
        String refreshToken,
        Instant refreshTokenExpiresAt,
        UUID sessionId,
        boolean emailVerified
) {
    public record TokenPair(
            String accessToken,
            Instant accessTokenExpiresAt,
            String refreshToken,
            Instant refreshTokenExpiresAt,
            UUID sessionId
    ) {}
}