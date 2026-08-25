package com.excellentcalendar.cloud.userdevice.api;

import java.time.Instant;
import java.util.UUID;

/**
 * Matches {@code contracts/user/avatar_info.schema.json}. Object-storage keys are never exposed.
 */
public record AvatarInfoResponseDto(
        UUID assetId,
        String url,
        String thumbnailUrl,
        String etag,
        Instant updatedAt) {
}
