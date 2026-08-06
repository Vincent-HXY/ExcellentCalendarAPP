package com.excellentcalendar.cloud.identity.application;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

/**
 * Aggregated current user data for the API response.
 */
public record CurrentUserResult(
        AccountInfo account,
        ProfileInfo profile,
        PreferencesInfo preferences
) {
    public record AccountInfo(
            UUID id, String email, String status,
            Instant emailVerifiedAt, Instant createdAt, Instant updatedAt
    ) {}

    public record ProfileInfo(
            UUID userId, String username, String displayName,
            AvatarInfo avatar, Instant createdAt, Instant updatedAt
    ) {}

    public record AvatarInfo(
            UUID assetId, String url, String thumbnailUrl,
            String etag, Instant updatedAt
    ) {}

    public record PreferencesInfo(
            UUID userId, String locale, String timezone,
            String[] defaultReminderMethods, Map<String, Object> settings,
            Instant createdAt, Instant updatedAt
    ) {}
}