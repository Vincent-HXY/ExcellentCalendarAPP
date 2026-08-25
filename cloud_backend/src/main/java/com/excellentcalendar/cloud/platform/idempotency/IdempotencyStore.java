package com.excellentcalendar.cloud.platform.idempotency;

import java.time.Clock;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * Storage for idempotency-key records. Every operation runs in its own transaction so a claim is
 * visible to concurrent duplicates immediately and survives the business transaction outcome.
 * Records expire after the configured TTL: expired rows are never replayed, an expired claim is
 * atomically taken over (a crashed claim can no longer wedge its key), and every successful claim
 * opportunistically removes a bounded batch of expired rows so the table stays bounded.
 */
@Service
public class IdempotencyStore {

    private static final int CLEANUP_BATCH_SIZE = 100;

    private final IdempotencyRecordRepository repository;
    private final Clock clock;
    private final IdempotencyProperties properties;

    public IdempotencyStore(
            IdempotencyRecordRepository repository,
            Clock clock,
            IdempotencyProperties properties) {
        this.repository = repository;
        this.clock = clock;
        this.properties = properties;
    }

    public record StoredResponse(Integer status, byte[] body) {
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public boolean tryClaim(String scope, String keyHash) {
        Instant now = clock.instant();
        int inserted = repository.insertOrTakeOverExpired(
                UUID.randomUUID(),
                scope,
                keyHash,
                now,
                now.plusSeconds(properties.getTtlHours() * 3600),
                now);
        if (inserted == 1) {
            repository.deleteExpiredBatch(now, CLEANUP_BATCH_SIZE);
        }
        return inserted == 1;
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW, readOnly = true)
    public Optional<StoredResponse> findStored(String scope, String keyHash) {
        return repository.findByScopeAndKeyHashAndExpiresAtGreaterThan(scope, keyHash, clock.instant())
                .filter(record -> record.getResponseStatus() != null)
                .map(record -> new StoredResponse(record.getResponseStatus(), record.getResponseBody()));
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void complete(String scope, String keyHash, int status, byte[] body) {
        repository.complete(scope, keyHash, status, body);
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void release(String scope, String keyHash) {
        repository.deleteByScopeAndKeyHash(scope, keyHash);
    }
}
