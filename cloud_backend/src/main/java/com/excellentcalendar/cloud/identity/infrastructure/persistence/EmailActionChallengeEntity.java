package com.excellentcalendar.cloud.identity.infrastructure.persistence;

import com.excellentcalendar.cloud.identity.domain.EmailActionPurpose;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "email_action_challenges")
public class EmailActionChallengeEntity {

    @Id
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 32)
    private EmailActionPurpose purpose;

    @Column(name = "target_email", nullable = false, length = 254)
    private String targetEmail;

    @Column(name = "code_hash", length = 64)
    private String codeHash;

    @Column(name = "link_token_hash", length = 64)
    private String linkTokenHash;

    @Column(name = "failed_attempt_count", nullable = false)
    private int failedAttemptCount;

    @Column(name = "max_attempts", nullable = false)
    private int maxAttempts;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @Column(name = "resend_available_at", nullable = false)
    private Instant resendAvailableAt;

    @Column(name = "consumed_at")
    private Instant consumedAt;

    @Column(name = "invalidated_at")
    private Instant invalidatedAt;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected EmailActionChallengeEntity() {
    }

    public EmailActionChallengeEntity(
            UUID id,
            UUID userId,
            EmailActionPurpose purpose,
            String targetEmail,
            String codeHash,
            int maxAttempts,
            Instant expiresAt,
            Instant resendAvailableAt,
            Instant createdAt) {
        this.id = id;
        this.userId = userId;
        this.purpose = purpose;
        this.targetEmail = targetEmail;
        this.codeHash = codeHash;
        this.maxAttempts = maxAttempts;
        this.expiresAt = expiresAt;
        this.resendAvailableAt = resendAvailableAt;
        this.createdAt = createdAt;
    }

    public UUID getId() {
        return id;
    }

    public UUID getUserId() {
        return userId;
    }

    public EmailActionPurpose getPurpose() {
        return purpose;
    }

    public String getTargetEmail() {
        return targetEmail;
    }

    public String getCodeHash() {
        return codeHash;
    }

    public int getFailedAttemptCount() {
        return failedAttemptCount;
    }

    public int getMaxAttempts() {
        return maxAttempts;
    }

    public Instant getExpiresAt() {
        return expiresAt;
    }

    public Instant getResendAvailableAt() {
        return resendAvailableAt;
    }

    public Instant getConsumedAt() {
        return consumedAt;
    }

    public Instant getInvalidatedAt() {
        return invalidatedAt;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public boolean isConsumed() {
        return consumedAt != null;
    }

    public boolean isInvalidated() {
        return invalidatedAt != null;
    }

    public void recordFailedAttempt(Instant now) {
        failedAttemptCount++;
        if (failedAttemptCount >= maxAttempts) {
            invalidatedAt = now;
        }
    }

    public void consume(Instant now) {
        consumedAt = now;
    }

    public void invalidate(Instant now) {
        if (invalidatedAt == null) {
            invalidatedAt = now;
        }
    }
}
