package com.excellentcalendar.cloud.identity.domain;

import java.time.Clock;
import java.time.Instant;
import java.util.UUID;

/**
 * Root identity record for every registered user.
 */
public class UserAccount {

    private final UUID id;
    private String email;
    private String passwordHash;
    private UserAccountStatus status;
    private Instant emailVerifiedAt;
    private final String agreementVersion;
    private final boolean agreementAccepted;
    private final Instant createdAt;
    private Instant updatedAt;

    public UserAccount(
            UUID id, String email, String passwordHash, UserAccountStatus status,
            Instant emailVerifiedAt, String agreementVersion, boolean agreementAccepted,
            Instant createdAt, Instant updatedAt) {
        this.id = id;
        this.email = email;
        this.passwordHash = passwordHash;
        this.status = status;
        this.emailVerifiedAt = emailVerifiedAt;
        this.agreementVersion = agreementVersion;
        this.agreementAccepted = agreementAccepted;
        this.createdAt = createdAt;
        this.updatedAt = updatedAt;
    }

    public static UserAccount createPending(String email, String passwordHash,
                                            String agreementVersion, boolean agreementAccepted,
                                            Clock clock) {
        Instant now = clock.instant();
        return new UserAccount(
                UUID.randomUUID(), email.toLowerCase(), passwordHash,
                UserAccountStatus.PENDING_VERIFICATION, null,
                agreementVersion, agreementAccepted, now, now);
    }

    public void verifyEmail(Clock clock) {
        if (status == UserAccountStatus.ACTIVE) {
            return; // idempotent
        }
        if (status != UserAccountStatus.PENDING_VERIFICATION) {
            throw new IllegalStateException("Account cannot be verified in status: " + status);
        }
        this.status = UserAccountStatus.ACTIVE;
        this.emailVerifiedAt = clock.instant();
        this.updatedAt = clock.instant();
    }

    public void updatePassword(String newPasswordHash, Clock clock) {
        this.passwordHash = newPasswordHash;
        this.updatedAt = clock.instant();
    }

    public void changeEmail(String newEmail, Clock clock) {
        this.email = newEmail.toLowerCase();
        this.updatedAt = clock.instant();
    }

    public void markDisabled(Clock clock) {
        this.status = UserAccountStatus.DISABLED;
        this.updatedAt = clock.instant();
    }

    // Getters

    public UUID getId() { return id; }
    public String getEmail() { return email; }
    public String getPasswordHash() { return passwordHash; }
    public UserAccountStatus getStatus() { return status; }
    public Instant getEmailVerifiedAt() { return emailVerifiedAt; }
    public String getAgreementVersion() { return agreementVersion; }
    public boolean isAgreementAccepted() { return agreementAccepted; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }

    public boolean isActive() { return status == UserAccountStatus.ACTIVE; }
    public boolean isPendingVerification() { return status == UserAccountStatus.PENDING_VERIFICATION; }
    public boolean isDisabled() { return status == UserAccountStatus.DISABLED; }
    public boolean isDeleted() { return status == UserAccountStatus.DELETED; }
    public boolean isEmailVerified() { return emailVerifiedAt != null; }
}