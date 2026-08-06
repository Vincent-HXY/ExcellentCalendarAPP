package com.excellentcalendar.cloud.identity.domain;

import java.time.Clock;
import java.time.Instant;
import java.util.UUID;

/**
 * One row = one refresh token issuance in a rotating family.
 */
public class RefreshTokenGrant {

    private final UUID id;
    private final UUID userId;
    private final UUID sessionId;
    private String tokenHash;
    private final UUID familyId;
    private final UUID parentId;
    private RefreshTokenGrantStatus status;
    private final Instant expiresAt;
    private Instant revokedAt;
    private String revocationReason;
    private final Instant createdAt;

    public RefreshTokenGrant(
            UUID id, UUID userId, UUID sessionId, String tokenHash,
            UUID familyId, UUID parentId, RefreshTokenGrantStatus status,
            Instant expiresAt, Instant revokedAt, String revocationReason, Instant createdAt) {
        this.id = id;
        this.userId = userId;
        this.sessionId = sessionId;
        this.tokenHash = tokenHash;
        this.familyId = familyId;
        this.parentId = parentId;
        this.status = status;
        this.expiresAt = expiresAt;
        this.revokedAt = revokedAt;
        this.revocationReason = revocationReason;
        this.createdAt = createdAt;
    }

    public static RefreshTokenGrant createRoot(
            UUID userId, UUID sessionId, String tokenHash,
            Instant expiresAt) {
        UUID familyId = UUID.randomUUID();
        return new RefreshTokenGrant(
                UUID.randomUUID(), userId, sessionId, tokenHash,
                familyId, null, RefreshTokenGrantStatus.ACTIVE,
                expiresAt, null, null, Clock.systemUTC().instant());
    }

    public static RefreshTokenGrant createChild(
            UUID userId, UUID sessionId, String tokenHash,
            UUID familyId, UUID parentId, Instant expiresAt) {
        return new RefreshTokenGrant(
                UUID.randomUUID(), userId, sessionId, tokenHash,
                familyId, parentId, RefreshTokenGrantStatus.ACTIVE,
                expiresAt, null, null, Clock.systemUTC().instant());
    }

    public void consume() {
        if (status != RefreshTokenGrantStatus.ACTIVE) {
            throw new IllegalStateException("Cannot consume a " + status + " grant");
        }
        this.status = RefreshTokenGrantStatus.CONSUMED;
    }

    public void revoke(String reason, Clock clock) {
        if (status == RefreshTokenGrantStatus.REVOKED) return;
        this.status = RefreshTokenGrantStatus.REVOKED;
        this.revokedAt = clock.instant();
        this.revocationReason = reason;
    }

    public void markExpired() {
        this.status = RefreshTokenGrantStatus.EXPIRED;
    }

    public boolean isActive() { return status == RefreshTokenGrantStatus.ACTIVE; }
    public boolean isConsumed() { return status == RefreshTokenGrantStatus.CONSUMED; }
    public boolean isRevoked() { return status == RefreshTokenGrantStatus.REVOKED; }
    public boolean isExpired(Clock clock) { return expiresAt.isBefore(clock.instant()); }

    // Getters

    public UUID getId() { return id; }
    public UUID getUserId() { return userId; }
    public UUID getSessionId() { return sessionId; }
    public String getTokenHash() { return tokenHash; }
    public UUID getFamilyId() { return familyId; }
    public UUID getParentId() { return parentId; }
    public RefreshTokenGrantStatus getStatus() { return status; }
    public Instant getExpiresAt() { return expiresAt; }
    public Instant getRevokedAt() { return revokedAt; }
    public String getRevocationReason() { return revocationReason; }
    public Instant getCreatedAt() { return createdAt; }
}