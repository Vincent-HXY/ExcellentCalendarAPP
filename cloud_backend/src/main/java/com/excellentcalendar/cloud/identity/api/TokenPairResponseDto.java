package com.excellentcalendar.cloud.identity.api;

import java.time.Instant;
import java.util.UUID;

public record TokenPairResponseDto(
        String tokenType,
        String accessToken,
        Instant accessTokenExpiresAt,
        String refreshToken,
        Instant refreshTokenExpiresAt,
        UUID sessionId) {

    public static TokenPairResponseDto from(
            com.excellentcalendar.cloud.identity.application.AuthenticationResults.TokenPair tokens) {
        return new TokenPairResponseDto(
                "Bearer",
                tokens.accessToken(),
                tokens.accessTokenExpiresAt(),
                tokens.refreshToken(),
                tokens.refreshTokenExpiresAt(),
                tokens.sessionId());
    }
}
