package com.excellentcalendar.cloud.identity.infrastructure.persistence;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.repository.Repository;

public interface UserSessionRepository extends Repository<UserSessionEntity, UUID> {

    UserSessionEntity save(UserSessionEntity entity);

    Optional<UserSessionEntity> findById(UUID id);

    List<UserSessionEntity> findByUserIdAndRevokedAtIsNull(UUID userId);

    List<UserSessionEntity> findByUserId(UUID userId);
}
