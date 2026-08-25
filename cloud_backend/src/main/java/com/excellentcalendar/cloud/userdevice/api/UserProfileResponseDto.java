package com.excellentcalendar.cloud.userdevice.api;

import java.time.Instant;
import java.util.UUID;

public record UserProfileResponseDto(
        UUID userId,
        String username,
        String displayName,
        AvatarInfoResponseDto avatar,
        Instant createdAt,
        Instant updatedAt) {
}
