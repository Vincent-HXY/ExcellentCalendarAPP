package com.excellentcalendar.cloud.userdevice.infrastructure.persistence;

import java.util.Optional;
import java.util.UUID;
import org.springframework.data.repository.Repository;

public interface UserProfileRepository extends Repository<UserProfileEntity, UUID> {

    UserProfileEntity save(UserProfileEntity entity);

    UserProfileEntity saveAndFlush(UserProfileEntity entity);

    Optional<UserProfileEntity> findById(UUID userId);

    boolean existsByNormalizedUsernameAndUserIdNot(String normalizedUsername, UUID userId);
}
