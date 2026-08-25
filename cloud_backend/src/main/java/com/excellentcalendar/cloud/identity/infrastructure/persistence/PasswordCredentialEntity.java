package com.excellentcalendar.cloud.identity.infrastructure.persistence;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "password_credentials")
public class PasswordCredentialEntity {

    public static final String ALGORITHM_ARGON2ID = "argon2id";

    @Id
    @Column(name = "user_id")
    private UUID userId;

    @Column(name = "password_hash", nullable = false, length = 512)
    private String passwordHash;

    @Column(nullable = false, length = 32)
    private String algorithm;

    @Column(name = "password_changed_at", nullable = false)
    private Instant passwordChangedAt;

    protected PasswordCredentialEntity() {
    }

    public PasswordCredentialEntity(UUID userId, String passwordHash, Instant passwordChangedAt) {
        this.userId = userId;
        this.passwordHash = passwordHash;
        this.algorithm = ALGORITHM_ARGON2ID;
        this.passwordChangedAt = passwordChangedAt;
    }

    public UUID getUserId() {
        return userId;
    }

    public String getPasswordHash() {
        return passwordHash;
    }

    public String getAlgorithm() {
        return algorithm;
    }

    public Instant getPasswordChangedAt() {
        return passwordChangedAt;
    }

    public void replaceHash(String newHash, Instant now) {
        this.passwordHash = newHash;
        this.passwordChangedAt = now;
    }
}
