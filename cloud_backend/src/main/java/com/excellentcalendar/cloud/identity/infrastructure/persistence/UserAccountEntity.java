package com.excellentcalendar.cloud.identity.infrastructure.persistence;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "user_accounts")
public class UserAccountEntity {

    @Id
    private UUID id;

    @Column(nullable = false, length = 254)
    private String email;

    @Column(name = "normalized_email", nullable = false, length = 254)
    private String normalizedEmail;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 32)
    private com.excellentcalendar.cloud.identity.domain.UserAccountStatus status;

    @Column(name = "email_verified_at")
    private Instant emailVerifiedAt;

    @Column(name = "disabled_at")
    private Instant disabledAt;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Column(name = "deleted_at")
    private Instant deletedAt;

    protected UserAccountEntity() {
    }

    public UserAccountEntity(
            UUID id,
            String email,
            String normalizedEmail,
            com.excellentcalendar.cloud.identity.domain.UserAccountStatus status,
            Instant createdAt) {
        this.id = id;
        this.email = email;
        this.normalizedEmail = normalizedEmail;
        this.status = status;
        this.createdAt = createdAt;
        this.updatedAt = createdAt;
    }

    public UUID getId() {
        return id;
    }

    public String getEmail() {
        return email;
    }

    public String getNormalizedEmail() {
        return normalizedEmail;
    }

    public com.excellentcalendar.cloud.identity.domain.UserAccountStatus getStatus() {
        return status;
    }

    public Instant getEmailVerifiedAt() {
        return emailVerifiedAt;
    }

    public Instant getDisabledAt() {
        return disabledAt;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public Instant getDeletedAt() {
        return deletedAt;
    }

    public void activate(Instant now) {
        this.status = com.excellentcalendar.cloud.identity.domain.UserAccountStatus.active;
        this.emailVerifiedAt = now;
        this.updatedAt = now;
    }

    public void replaceEmail(String newEmail, String normalizedNewEmail, Instant now) {
        this.email = newEmail;
        this.normalizedEmail = normalizedNewEmail;
        this.emailVerifiedAt = now;
        this.updatedAt = now;
    }
}
