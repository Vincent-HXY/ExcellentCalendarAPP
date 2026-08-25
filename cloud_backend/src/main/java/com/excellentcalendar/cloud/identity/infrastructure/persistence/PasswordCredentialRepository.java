package com.excellentcalendar.cloud.identity.infrastructure.persistence;

import java.util.Optional;
import java.util.UUID;
import org.springframework.data.repository.Repository;

public interface PasswordCredentialRepository extends Repository<PasswordCredentialEntity, UUID> {

    PasswordCredentialEntity save(PasswordCredentialEntity entity);

    Optional<PasswordCredentialEntity> findById(UUID userId);
}
