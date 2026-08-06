package com.excellentcalendar.cloud.userdevice.domain;

import java.time.Instant;
import java.util.UUID;

/**
 * Public profile for the authenticated user.
 */
public class UserProfile {

    private final UUID userId;
    private String username;
    private String displayName;
    private UUID avatarAssetId;
    private String avatarUrl;
    private String avatarThumbnailUrl;
    private String avatarEtag;
    private Instant avatarUpdatedAt;
    private final Instant createdAt;
    private Instant updatedAt;

    public UserProfile(
            UUID userId, String username, String displayName,
            UUID avatarAssetId, String avatarUrl, String avatarThumbnailUrl,
            String avatarEtag, Instant avatarUpdatedAt,
            Instant createdAt, Instant updatedAt) {
        this.userId = userId;
        this.username = username;
        this.displayName = displayName;
        this.avatarAssetId = avatarAssetId;
        this.avatarUrl = avatarUrl;
        this.avatarThumbnailUrl = avatarThumbnailUrl;
        this.avatarEtag = avatarEtag;
        this.avatarUpdatedAt = avatarUpdatedAt;
        this.createdAt = createdAt;
        this.updatedAt = updatedAt;
    }

    public void updateProfile(String username, String displayName, java.time.Clock clock) {
        this.username = username;
        this.displayName = displayName;
        this.updatedAt = clock.instant();
    }

    public void updateAvatar(UUID assetId, String url, String thumbnailUrl, String etag, java.time.Clock clock) {
        this.avatarAssetId = assetId;
        this.avatarUrl = url;
        this.avatarThumbnailUrl = thumbnailUrl;
        this.avatarEtag = etag;
        this.avatarUpdatedAt = clock.instant();
        this.updatedAt = clock.instant();
    }

    public void removeAvatar(java.time.Clock clock) {
        this.avatarAssetId = null;
        this.avatarUrl = null;
        this.avatarThumbnailUrl = null;
        this.avatarEtag = null;
        this.avatarUpdatedAt = null;
        this.updatedAt = clock.instant();
    }

    // Getters

    public UUID getUserId() { return userId; }
    public String getUsername() { return username; }
    public String getDisplayName() { return displayName; }
    public UUID getAvatarAssetId() { return avatarAssetId; }
    public String getAvatarUrl() { return avatarUrl; }
    public String getAvatarThumbnailUrl() { return avatarThumbnailUrl; }
    public String getAvatarEtag() { return avatarEtag; }
    public Instant getAvatarUpdatedAt() { return avatarUpdatedAt; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
    public boolean hasAvatar() { return avatarAssetId != null; }
}