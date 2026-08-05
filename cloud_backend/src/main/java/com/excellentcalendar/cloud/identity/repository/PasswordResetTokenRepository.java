package com.excellentcalendar.cloud.identity.repository;

import com.excellentcalendar.cloud.identity.model.PasswordResetToken;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface PasswordResetTokenRepository extends JpaRepository<PasswordResetToken, UUID> {

    Optional<PasswordResetToken> findTopByUserAccountIdAndUsedAtIsNullOrderByCreatedAtDesc(UUID userAccountId);

    Optional<PasswordResetToken> findTopByTokenHashAndUsedAtIsNullOrderByCreatedAtDesc(String tokenHash);

    void deleteByUserAccountId(UUID userAccountId);
}