package com.excellentcalendar.cloud.platform.idempotency;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.Repository;

public interface IdempotencyRecordRepository extends Repository<IdempotencyRecordEntity, UUID> {

    /**
     * Claims a key, or atomically takes over an expired row (a crashed claim or a record whose TTL
     * has passed). Returns 1 when this call owns the key, 0 when a fresh competing record exists.
     */
    @Modifying
    @Query(value = """
            INSERT INTO idempotency_records (id, scope, key_hash, created_at, expires_at)
            VALUES (:id, :scope, :keyHash, :createdAt, :expiresAt)
            ON CONFLICT (scope, key_hash) DO UPDATE
                SET id = EXCLUDED.id,
                    created_at = EXCLUDED.created_at,
                    expires_at = EXCLUDED.expires_at,
                    response_status = NULL,
                    response_body = NULL
                WHERE idempotency_records.expires_at <= :now
            """, nativeQuery = true)
    int insertOrTakeOverExpired(
            UUID id, String scope, String keyHash, Instant createdAt, Instant expiresAt, Instant now);

    Optional<IdempotencyRecordEntity> findByScopeAndKeyHashAndExpiresAtGreaterThan(
            String scope, String keyHash, Instant now);

    @Modifying
    @Query("""
            UPDATE IdempotencyRecordEntity record
            SET record.responseStatus = :status, record.responseBody = :body
            WHERE record.scope = :scope AND record.keyHash = :keyHash
            """)
    int complete(String scope, String keyHash, Integer status, byte[] body);

    @Modifying
    int deleteByScopeAndKeyHash(String scope, String keyHash);

    /**
     * Bounded housekeeping: removes up to {@code batch} expired rows using the expires_at index.
     * Safe to run concurrently on every instance.
     */
    @Modifying
    @Query(value = """
            DELETE FROM idempotency_records
            WHERE id IN (
                SELECT id FROM idempotency_records WHERE expires_at <= :now LIMIT :batch)
            """, nativeQuery = true)
    int deleteExpiredBatch(Instant now, int batch);
}
