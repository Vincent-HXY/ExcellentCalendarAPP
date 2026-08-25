package com.excellentcalendar.cloud.identity.infrastructure.persistence;

import com.excellentcalendar.cloud.identity.domain.EmailChangeStatus;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "email_change_requests")
public class EmailChangeRequestEntity {

    @Id
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "old_email", nullable = false, length = 254)
    private String oldEmail;

    @Column(name = "new_email", nullable = false, length = 254)
    private String newEmail;

    @Column(name = "challenge_id", nullable = false)
    private UUID challengeId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    private EmailChangeStatus status;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @Column(name = "completed_at")
    private Instant completedAt;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected EmailChangeRequestEntity() {
    }

    public EmailChangeRequestEntity(
            UUID id,
            UUID userId,
            String oldEmail,
            String newEmail,
            UUID challengeId,
            Instant expiresAt,
            Instant createdAt) {
        this.id = id;
        this.userId = userId;
        this.oldEmail = oldEmail;
        this.newEmail = newEmail;
        this.challengeId = challengeId;
        this.status = EmailChangeStatus.pending;
        this.expiresAt = expiresAt;
        this.createdAt = createdAt;
    }

    public UUID getId() {
        return id;
    }

    public UUID getUserId() {
        return userId;
    }

    public String getOldEmail() {
        return oldEmail;
    }

    public String getNewEmail() {
        return newEmail;
    }

    public UUID getChallengeId() {
        return challengeId;
    }

    public EmailChangeStatus getStatus() {
        return status;
    }

    public Instant getExpiresAt() {
        return expiresAt;
    }

    public Instant getCompletedAt() {
        return completedAt;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public void cancel(Instant now) {
        this.status = EmailChangeStatus.cancelled;
    }

    public void complete(Instant now) {
        this.status = EmailChangeStatus.verified;
        this.completedAt = now;
    }

    public void markExpired(Instant now) {
        this.status = EmailChangeStatus.expired;
    }
}
