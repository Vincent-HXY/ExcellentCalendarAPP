package com.excellentcalendar.cloud.platform.idempotency;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

/**
 * Persisted Idempotency-Key record. The row is claimed before business execution and stores the
 * final HTTP response bytes for replays; failed executions release the claim so retries with the
 * same key can execute again.
 */
@Entity
@Table(name = "idempotency_records")
public class IdempotencyRecordEntity {

    @Id
    private UUID id;

    @Column(name = "scope", nullable = false, length = 96)
    private String scope;

    @Column(name = "key_hash", nullable = false, length = 64)
    private String keyHash;

    @Column(name = "request_digest", length = 64)
    private String requestDigest;

    @Column(name = "response_status")
    private Integer responseStatus;

    @Column(name = "response_body")
    private byte[] responseBody;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    protected IdempotencyRecordEntity() {
    }

    public IdempotencyRecordEntity(UUID id, String scope, String keyHash, Instant createdAt, Instant expiresAt) {
        this.id = id;
        this.scope = scope;
        this.keyHash = keyHash;
        this.createdAt = createdAt;
        this.expiresAt = expiresAt;
    }

    public UUID getId() {
        return id;
    }

    public String getScope() {
        return scope;
    }

    public String getKeyHash() {
        return keyHash;
    }

    public Integer getResponseStatus() {
        return responseStatus;
    }

    public byte[] getResponseBody() {
        return responseBody;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getExpiresAt() {
        return expiresAt;
    }
}
