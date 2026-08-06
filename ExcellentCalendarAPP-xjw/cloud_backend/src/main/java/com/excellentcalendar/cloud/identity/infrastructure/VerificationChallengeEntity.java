package com.excellentcalendar.cloud.identity.infrastructure;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

/**
 * JPA entity mapping the {@code verification_challenge} table.
 */
@Entity
@Table(name = "verification_challenge")
public class VerificationChallengeEntity {

    @Id
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(nullable = false)
    private String purpose;

    @Column(name = "masked_email", nullable = false)
    private String maskedEmail;

    @Column(name = "credential_types", columnDefinition = "TEXT[]")
    private String[] credentialTypes;

    @Column(name = "code_hash")
    private String codeHash;

    @Column(name = "link_token_hash")
    private String linkTokenHash;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @Column(name = "failed_attempts", nullable = false)
    private int failedAttempts;

    @Column(name = "max_attempts", nullable = false)
    private int maxAttempts;

    @Column(name = "consumed_at")
    private Instant consumedAt;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    public VerificationChallengeEntity() {}

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }

    public UUID getUserId() { return userId; }
    public void setUserId(UUID userId) { this.userId = userId; }

    public String getPurpose() { return purpose; }
    public void setPurpose(String purpose) { this.purpose = purpose; }

    public String getMaskedEmail() { return maskedEmail; }
    public void setMaskedEmail(String maskedEmail) { this.maskedEmail = maskedEmail; }

    public String[] getCredentialTypes() { return credentialTypes; }
    public void setCredentialTypes(String[] credentialTypes) { this.credentialTypes = credentialTypes; }

    public String getCodeHash() { return codeHash; }
    public void setCodeHash(String codeHash) { this.codeHash = codeHash; }

    public String getLinkTokenHash() { return linkTokenHash; }
    public void setLinkTokenHash(String linkTokenHash) { this.linkTokenHash = linkTokenHash; }

    public Instant getExpiresAt() { return expiresAt; }
    public void setExpiresAt(Instant expiresAt) { this.expiresAt = expiresAt; }

    public int getFailedAttempts() { return failedAttempts; }
    public void setFailedAttempts(int failedAttempts) { this.failedAttempts = failedAttempts; }

    public int getMaxAttempts() { return maxAttempts; }
    public void setMaxAttempts(int maxAttempts) { this.maxAttempts = maxAttempts; }

    public Instant getConsumedAt() { return consumedAt; }
    public void setConsumedAt(Instant consumedAt) { this.consumedAt = consumedAt; }

    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }
}