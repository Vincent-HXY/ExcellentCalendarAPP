package com.excellentcalendar.cloud.identity.dto.response;

import java.util.UUID;

public record ProfileResponse(
        UUID userId,
        String email,
        String username,
        String displayName,
        String avatarUrl,
        String language,
        String timezone,
        boolean emailVerified) {
}