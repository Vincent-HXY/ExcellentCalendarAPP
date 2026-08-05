package com.excellentcalendar.cloud.identity.dto.response;

import java.util.UUID;

public record AuthResponse(
        UUID userId,
        String email,
        String username,
        String displayName,
        String avatarUrl,
        String language,
        String timezone,
        boolean emailVerified,
        String accessToken,
        String refreshToken,
        long expiresIn) {
}