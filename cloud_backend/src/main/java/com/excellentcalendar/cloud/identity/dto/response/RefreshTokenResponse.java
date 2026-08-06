package com.excellentcalendar.cloud.identity.dto.response;

public record RefreshTokenResponse(
        String accessToken,
        String refreshToken,
        long expiresIn) {
}