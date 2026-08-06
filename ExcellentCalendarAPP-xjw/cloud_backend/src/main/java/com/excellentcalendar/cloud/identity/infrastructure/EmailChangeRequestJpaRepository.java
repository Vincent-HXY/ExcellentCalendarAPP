package com.excellentcalendar.cloud.identity.infrastructure;

import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

interface EmailChangeRequestJpaRepository extends JpaRepository<EmailChangeRequestEntity, UUID> {

    Optional<EmailChangeRequestEntity> findByIdAndUserId(UUID id, UUID userId);
}