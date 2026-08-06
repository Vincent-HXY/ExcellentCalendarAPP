package com.excellentcalendar.cloud.identity.domain;

import java.time.Clock;
import java.time.Instant;
import java.util.UUID;

/**
 * Pending email change request.
 */
public class EmailChangeRequest {

    private final UUID id;
    private final UUID userId;
    private final String oldEmail;
    private final String newEmail;
    private final UUID challengeId;
    private EmailChangeRequestStatus status;
    private final Instant expiresAt;
    private final Instant createdAt;
    private Instant updatedAt;

    public EmailChangeRequest(
            UUID id, UUID userId, String oldEmail, String newEmail,
            UUID challengeId, EmailChangeRequestStatus status,
            Instant expiresAt, Instant createdAt, Instant updatedAt) {
        this.id = id;
        this.userId = userId;
        this.oldEmail = oldEmail;
        this.newEmail = newEmail;
        this.challengeId = challengeId;
        this.status = status;
        this.expiresAt = expiresAt;
        this.createdAt = createdAt;
        this.updatedAt = updatedAt;
    }

    public static EmailChangeRequest createPending(
            UUID userId, String oldEmail, String newEmail,
            UUID challengeId, Instant expiresAt, Clock clock) {
        return new EmailChangeRequest(
                UUID.randomUUID(), userId, oldEmail, newEmail,
                challengeId, EmailChangeRequestStatus.PENDING,
                expiresAt, clock.instant(), clock.instant());
    }

    public void markVerified(Clock clock) {
        this.status = EmailChangeRequestStatus.VERIFIED;
        this.updatedAt = clock.instant();
    }

    public void markExpired() {
        this.status = EmailChangeRequestStatus.EXPIRED;
    }

    public void markCancelled(Clock clock) {
        this.status = EmailChangeRequestStatus.CANCELLED;
        this.updatedAt = clock.instant();
    }

    public boolean isPending() { return status == EmailChangeRequestStatus.PENDING; }
    public boolean isExpired(Clock clock) { return expiresAt.isBefore(clock.instant()); }

    // Getters

    public UUID getId() { return id; }
    public UUID getUserId() { return userId; }
    public String getOldEmail() { return oldEmail; }
    public String getNewEmail() { return newEmail; }
    public UUID getChallengeId() { return challengeId; }
    public EmailChangeRequestStatus getStatus() { return status; }
    public Instant getExpiresAt() { return expiresAt; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
}