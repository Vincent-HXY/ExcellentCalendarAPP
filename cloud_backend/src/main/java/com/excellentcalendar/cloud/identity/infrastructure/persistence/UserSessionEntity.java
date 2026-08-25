package com.excellentcalendar.cloud.identity.infrastructure.persistence;

import com.excellentcalendar.cloud.identity.domain.SessionRevocationReason;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "user_sessions")
public class UserSessionEntity {

    @Id
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "token_family_id", nullable = false)
    private UUID tokenFamilyId;

    @Column(nullable = false, length = 32)
    private String platform;

    @Column(name = "device_name", length = 128)
    private String deviceName;

    @Column(name = "app_version", length = 64)
    private String appVersion;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @Column(name = "last_used_at", nullable = false)
    private Instant lastUsedAt;

    @Column(name = "revoked_at")
    private Instant revokedAt;

    @Enumerated(EnumType.STRING)
    @Column(name = "revocation_reason", length = 32)
    private SessionRevocationReason revocationReason;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected UserSessionEntity() {
    }

    public UserSessionEntity(UUID id, UUID userId, UUID tokenFamilyId, Instant expiresAt, Instant now) {
        this.id = id;
        this.userId = userId;
        this.tokenFamilyId = tokenFamilyId;
        this.platform = "android";
        this.expiresAt = expiresAt;
        this.lastUsedAt = now;
        this.createdAt = now;
    }

    public UUID getId() {
        return id;
    }

    public UUID getUserId() {
        return userId;
    }

    public UUID getTokenFamilyId() {
        return tokenFamilyId;
    }

    public String getPlatform() {
        return platform;
    }

    public Instant getExpiresAt() {
        return expiresAt;
    }

    public Instant getLastUsedAt() {
        return lastUsedAt;
    }

    public Instant getRevokedAt() {
        return revokedAt;
    }

    public SessionRevocationReason getRevocationReason() {
        return revocationReason;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public boolean isRevoked() {
        return revokedAt != null;
    }

    public void touch(Instant now, Instant newExpiresAt) {
        this.lastUsedAt = now;
        this.expiresAt = newExpiresAt;
    }

    public void revoke(Instant now, SessionRevocationReason reason) {
        if (revokedAt == null) {
            this.revokedAt = now;
            this.revocationReason = reason;
        }
    }
}
