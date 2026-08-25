package com.excellentcalendar.cloud.identity.infrastructure.persistence;

import jakarta.persistence.LockModeType;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.repository.Repository;

public interface RefreshTokenGrantRepository extends Repository<RefreshTokenGrantEntity, UUID> {

    RefreshTokenGrantEntity save(RefreshTokenGrantEntity entity);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<RefreshTokenGrantEntity> findWithLockingByTokenHash(String tokenHash);

    List<RefreshTokenGrantEntity> findBySessionId(UUID sessionId);

    List<RefreshTokenGrantEntity> findBySessionIdIn(List<UUID> sessionIds);
}
