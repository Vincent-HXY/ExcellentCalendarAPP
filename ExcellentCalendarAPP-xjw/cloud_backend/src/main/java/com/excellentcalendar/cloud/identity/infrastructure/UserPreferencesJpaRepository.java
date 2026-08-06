package com.excellentcalendar.cloud.identity.infrastructure;

import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface UserPreferencesJpaRepository extends JpaRepository<UserPreferencesEntity, UUID> {

    Optional<UserPreferencesEntity> findByUserId(UUID userId);
}