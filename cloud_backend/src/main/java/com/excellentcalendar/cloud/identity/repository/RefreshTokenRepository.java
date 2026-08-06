package com.excellentcalendar.cloud.identity.repository;

import com.excellentcalendar.cloud.identity.model.RefreshToken;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface RefreshTokenRepository extends JpaRepository<RefreshToken, UUID> {

    Optional<RefreshToken> findByTokenHash(String tokenHash);

    List<RefreshToken> findByUserAccountIdAndRevokedAtIsNull(UUID userAccountId);

    long countByUserAccountIdAndRevokedAtIsNull(UUID userAccountId);

    void deleteByUserAccountId(UUID userAccountId);
}