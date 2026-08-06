package com.excellentcalendar.cloud.identity.domain;

import java.time.Clock;
import java.time.Instant;
import java.util.UUID;

/**
 * A one-time email challenge for verification, password reset, or email change.
 */
public class VerificationChallenge {

    private final UUID id;
    private final UUID userId;
    private final String purpose;
    private final String maskedEmail;
    private final String[] credentialTypes;
    private String codeHash;
    private String linkTokenHash;
    private final Instant expiresAt;
    private final int maxAttempts;
    private int failedAttempts;
    private Instant consumedAt;
    private final Instant createdAt;

    public VerificationChallenge(
            UUID id, UUID userId, String purpose, String maskedEmail,
            String[] credentialTypes, String codeHash, String linkTokenHash,
            Instant expiresAt, int maxAttempts, int failedAttempts,
            Instant consumedAt, Instant createdAt) {
        this.id = id;
        this.userId = userId;
        this.purpose = purpose;
        this.maskedEmail = maskedEmail;
        this.credentialTypes = credentialTypes;
        this.codeHash = codeHash;
        this.linkTokenHash = linkTokenHash;
        this.expiresAt = expiresAt;
        this.maxAttempts = maxAttempts;
        this.failedAttempts = failedAttempts;
        this.consumedAt = consumedAt;
        this.createdAt = createdAt;
    }

    public static VerificationChallenge createCodeChallenge(
            UUID userId, String purpose, String maskedEmail,
            String codeHash, Instant expiresAt, int maxAttempts) {
        return new VerificationChallenge(
                UUID.randomUUID(), userId, purpose, maskedEmail,
                new String[]{"code"}, codeHash, null,
                expiresAt, maxAttempts, 0, null, Clock.systemUTC().instant());
    }

    public static VerificationChallenge createLinkTokenChallenge(
            UUID userId, String purpose, String maskedEmail,
            String codeHash, String linkTokenHash, Instant expiresAt, int maxAttempts) {
        return new VerificationChallenge(
                UUID.randomUUID(), userId, purpose, maskedEmail,
                new String[]{"code", "link_token"}, codeHash, linkTokenHash,
                expiresAt, maxAttempts, 0, null, Clock.systemUTC().instant());
    }

    /**
     * Checks if the challenge is still valid (not expired, not consumed, not exceeded max attempts).
     */
    public boolean isValid(Clock clock) {
        return consumedAt == null
                && failedAttempts < maxAttempts
                && expiresAt.isAfter(clock.instant());
    }

    /**
     * Records a failed attempt. Returns true if max attempts exceeded.
     */
    public boolean recordFailedAttempt() {
        this.failedAttempts++;
        return failedAttempts >= maxAttempts;
    }

    /**
     * Marks the challenge as consumed (one-time use).
     */
    public void consume() {
        this.consumedAt = Clock.systemUTC().instant();
    }

    public boolean isConsumed() { return consumedAt != null; }
    public boolean isExpired(Clock clock) { return expiresAt.isBefore(clock.instant()); }
    public boolean hasExceededAttempts() { return failedAttempts >= maxAttempts; }

    // Getters

    public UUID getId() { return id; }
    public UUID getUserId() { return userId; }
    public String getPurpose() { return purpose; }
    public String getMaskedEmail() { return maskedEmail; }
    public String[] getCredentialTypes() { return credentialTypes; }
    public String getCodeHash() { return codeHash; }
    public String getLinkTokenHash() { return linkTokenHash; }
    public Instant getExpiresAt() { return expiresAt; }
    public int getMaxAttempts() { return maxAttempts; }
    public int getFailedAttempts() { return failedAttempts; }
    public Instant getConsumedAt() { return consumedAt; }
    public Instant getCreatedAt() { return createdAt; }
}