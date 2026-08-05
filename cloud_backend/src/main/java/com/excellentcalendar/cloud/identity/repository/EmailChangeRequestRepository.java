package com.excellentcalendar.cloud.identity.repository;

import com.excellentcalendar.cloud.identity.model.EmailChangeRequest;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface EmailChangeRequestRepository extends JpaRepository<EmailChangeRequest, UUID> {

    Optional<EmailChangeRequest> findTopByUserAccountIdAndCodeAndVerifiedAtIsNullOrderByCreatedAtDesc(
            UUID userAccountId, String code);

    void deleteByUserAccountId(UUID userAccountId);
}