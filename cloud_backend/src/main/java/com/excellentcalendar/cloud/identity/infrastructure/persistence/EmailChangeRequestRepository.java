package com.excellentcalendar.cloud.identity.infrastructure.persistence;

import jakarta.persistence.LockModeType;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.repository.Repository;

public interface EmailChangeRequestRepository extends Repository<EmailChangeRequestEntity, UUID> {

    EmailChangeRequestEntity save(EmailChangeRequestEntity entity);

    /**
     * Flush raises the pending-request partial-index violation inside the persister's retry loop
     * instead of at commit time.
     */
    EmailChangeRequestEntity saveAndFlush(EmailChangeRequestEntity entity);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<EmailChangeRequestEntity> findWithLockingById(UUID id);

    Optional<EmailChangeRequestEntity> findFirstByUserIdAndStatusOrderByCreatedAtDesc(
            UUID userId, com.excellentcalendar.cloud.identity.domain.EmailChangeStatus status);
}
