package com.excellentcalendar.cloud.identity.infrastructure;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

/**
 * JPA entity mapping the {@code user_profile} table.
 */
@Entity
@Table(name = "user_profile")
public class UserProfileEntity {

    @Id
    @Column(name = "user_id")
    private UUID userId;

    @Column(nullable = false)
    private String username;

    @Column(name = "display_name", nullable = false)
    private String displayName;

    @Column(name = "avatar_asset_id")
    private UUID avatarAssetId;

    @Column(name = "avatar_url")
    private String avatarUrl;

    @Column(name = "avatar_thumbnail_url")
    private String avatarThumbnailUrl;

    @Column(name = "avatar_etag")
    private String avatarEtag;

    @Column(name = "avatar_updated_at")
    private Instant avatarUpdatedAt;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    public UserProfileEntity() {}

    public UUID getUserId() { return userId; }
    public void setUserId(UUID userId) { this.userId = userId; }

    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }

    public String getDisplayName() { return displayName; }
    public void setDisplayName(String displayName) { this.displayName = displayName; }

    public UUID getAvatarAssetId() { return avatarAssetId; }
    public void setAvatarAssetId(UUID avatarAssetId) { this.avatarAssetId = avatarAssetId; }

    public String getAvatarUrl() { return avatarUrl; }
    public void setAvatarUrl(String avatarUrl) { this.avatarUrl = avatarUrl; }

    public String getAvatarThumbnailUrl() { return avatarThumbnailUrl; }
    public void setAvatarThumbnailUrl(String avatarThumbnailUrl) { this.avatarThumbnailUrl = avatarThumbnailUrl; }

    public String getAvatarEtag() { return avatarEtag; }
    public void setAvatarEtag(String avatarEtag) { this.avatarEtag = avatarEtag; }

    public Instant getAvatarUpdatedAt() { return avatarUpdatedAt; }
    public void setAvatarUpdatedAt(Instant avatarUpdatedAt) { this.avatarUpdatedAt = avatarUpdatedAt; }

    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }

    public Instant getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(Instant updatedAt) { this.updatedAt = updatedAt; }
}