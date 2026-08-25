package com.excellentcalendar.cloud.userdevice.infrastructure.persistence;

import java.util.Optional;
import java.util.UUID;
import org.springframework.data.repository.Repository;

public interface UserPreferencesRepository extends Repository<UserPreferencesEntity, UUID> {

    UserPreferencesEntity save(UserPreferencesEntity entity);

    Optional<UserPreferencesEntity> findById(UUID userId);
}
