package com.excellentcalendar.cloud.identity.infrastructure.persistence;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "user_agreement_acceptances")
public class UserAgreementAcceptanceEntity {

    @Id
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "agreement_version", nullable = false, length = 64)
    private String agreementVersion;

    @Column(name = "accepted_at", nullable = false)
    private Instant acceptedAt;

    protected UserAgreementAcceptanceEntity() {
    }

    public UserAgreementAcceptanceEntity(UUID id, UUID userId, String agreementVersion, Instant acceptedAt) {
        this.id = id;
        this.userId = userId;
        this.agreementVersion = agreementVersion;
        this.acceptedAt = acceptedAt;
    }

    public UUID getId() {
        return id;
    }

    public UUID getUserId() {
        return userId;
    }

    public String getAgreementVersion() {
        return agreementVersion;
    }

    public Instant getAcceptedAt() {
        return acceptedAt;
    }
}
