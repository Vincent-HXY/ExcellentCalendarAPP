package com.excellentcalendar.cloud.identity.infrastructure.persistence;

import com.excellentcalendar.cloud.identity.domain.EmailActionPurpose;
import jakarta.persistence.LockModeType;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.Repository;

public interface EmailActionChallengeRepository extends Repository<EmailActionChallengeEntity, UUID> {

    EmailActionChallengeEntity save(EmailActionChallengeEntity entity);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<EmailActionChallengeEntity> findWithLockingById(UUID id);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
            SELECT challenge FROM EmailActionChallengeEntity challenge
            WHERE challenge.userId = :userId
              AND challenge.purpose = :purpose
              AND challenge.consumedAt IS NULL
              AND challenge.invalidatedAt IS NULL
            ORDER BY challenge.createdAt DESC
            """)
    List<EmailActionChallengeEntity> findActiveWithLockingByUserIdAndPurpose(
            UUID userId, EmailActionPurpose purpose);

    /**
     * Latest challenge of a purpose regardless of lifecycle, so consumed/invalidated/expired
     * outcomes can be reported distinctly instead of collapsing into "no active challenge".
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
            SELECT challenge FROM EmailActionChallengeEntity challenge
            WHERE challenge.userId = :userId
              AND challenge.purpose = :purpose
            ORDER BY challenge.createdAt DESC
            """)
    List<EmailActionChallengeEntity> findLatestWithLockingByUserIdAndPurpose(
            UUID userId, EmailActionPurpose purpose);

    @Modifying
    @Query("""
            UPDATE EmailActionChallengeEntity challenge
            SET challenge.invalidatedAt = :now
            WHERE challenge.userId = :userId
              AND challenge.purpose = :purpose
              AND challenge.consumedAt IS NULL
              AND challenge.invalidatedAt IS NULL
            """)
    int invalidateActiveByUserAndPurpose(UUID userId, EmailActionPurpose purpose, Instant now);
}
