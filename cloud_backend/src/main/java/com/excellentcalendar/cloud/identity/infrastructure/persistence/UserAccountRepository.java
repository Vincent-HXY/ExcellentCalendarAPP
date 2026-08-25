package com.excellentcalendar.cloud.identity.infrastructure.persistence;

import java.util.Optional;
import java.util.UUID;
import org.springframework.data.repository.Repository;

public interface UserAccountRepository extends Repository<UserAccountEntity, UUID> {

    UserAccountEntity save(UserAccountEntity entity);

    UserAccountEntity saveAndFlush(UserAccountEntity entity);

    Optional<UserAccountEntity> findById(UUID id);

    Optional<UserAccountEntity> findByNormalizedEmail(String normalizedEmail);
}
