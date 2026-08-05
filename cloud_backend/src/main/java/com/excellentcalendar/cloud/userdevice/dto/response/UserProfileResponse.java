package com.excellentcalendar.cloud.userdevice.dto.response;

import java.util.UUID;

public record UserProfileResponse(
        UUID userId,
        String displayName,
        String username,
        String avatarUrl,
        String language,
        String timezone) {
}