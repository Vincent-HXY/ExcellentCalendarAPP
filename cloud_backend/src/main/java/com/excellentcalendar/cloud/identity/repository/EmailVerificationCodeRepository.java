package com.excellentcalendar.cloud.identity.repository;

import com.excellentcalendar.cloud.identity.model.EmailVerificationCode;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface EmailVerificationCodeRepository extends JpaRepository<EmailVerificationCode, UUID> {

    Optional<EmailVerificationCode> findTopByUserAccountIdAndCodeAndVerifiedAtIsNullOrderByCreatedAtDesc(
            UUID userAccountId, String code);

    long countByUserAccountIdAndCreatedAtAfter(UUID userAccountId, java.time.Instant since);

    void deleteByUserAccountId(UUID userAccountId);
}