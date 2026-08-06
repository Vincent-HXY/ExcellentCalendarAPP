package com.excellentcalendar.cloud.identity.domain;

import java.util.Optional;
import java.util.UUID;

/**
 * Port for persisting and loading email change requests.
 */
public interface EmailChangeRequestRepository {

    void save(EmailChangeRequest request);

    Optional<EmailChangeRequest> findById(UUID id);

    Optional<EmailChangeRequest> findByIdAndUserId(UUID id, UUID userId);
}