package com.excellentcalendar.cloud.userdevice.infrastructure.persistence;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "user_profiles")
public class UserProfileEntity {

    @Id
    @Column(name = "user_id")
    private UUID userId;

    @Column(nullable = false, length = 24)
    private String username;

    @Column(name = "normalized_username", nullable = false, length = 24)
    private String normalizedUsername;

    @Column(name = "display_name", nullable = false, length = 40)
    private String displayName;

    @Column(name = "avatar_asset_id")
    private UUID avatarAssetId;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected UserProfileEntity() {
    }

    public UserProfileEntity(
            UUID userId, String username, String normalizedUsername, String displayName, Instant now) {
        this.userId = userId;
        this.username = username;
        this.normalizedUsername = normalizedUsername;
        this.displayName = displayName;
        this.createdAt = now;
        this.updatedAt = now;
    }

    public UUID getUserId() {
        return userId;
    }

    public String getUsername() {
        return username;
    }

    public String getNormalizedUsername() {
        return normalizedUsername;
    }

    public String getDisplayName() {
        return displayName;
    }

    public UUID getAvatarAssetId() {
        return avatarAssetId;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public void updateUsername(String username, String normalizedUsername, Instant now) {
        this.username = username;
        this.normalizedUsername = normalizedUsername;
        this.updatedAt = now;
    }

    public void updateDisplayName(String displayName, Instant now) {
        this.displayName = displayName;
        this.updatedAt = now;
    }

    public void updateAvatarAsset(UUID assetId, Instant now) {
        this.avatarAssetId = assetId;
        this.updatedAt = now;
    }
}
