package com.excellentcalendar.cloud.identity.infrastructure;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;

interface RefreshTokenGrantJpaRepository extends JpaRepository<RefreshTokenGrantEntity, UUID> {

    Optional<RefreshTokenGrantEntity> findByTokenHash(String tokenHash);

    List<RefreshTokenGrantEntity> findByFamilyId(UUID familyId);

    List<RefreshTokenGrantEntity> findByUserId(UUID userId);

    @Query("select r from RefreshTokenGrantEntity r where r.userId = :userId and r.status = 'active'")
    List<RefreshTokenGrantEntity> findActiveByUserId(UUID userId);

    @Modifying
    @Query("update RefreshTokenGrantEntity r set r.status = 'revoked', r.revokedAt = CURRENT_TIMESTAMP, r.revocationReason = :reason where r.userId = :userId and r.status = 'active'")
    void revokeAllActiveByUserId(UUID userId, String reason);

    @Modifying
    @Query("update RefreshTokenGrantEntity r set r.status = 'revoked', r.revokedAt = CURRENT_TIMESTAMP, r.revocationReason = :reason where r.familyId = :familyId")
    void revokeAllByFamilyId(UUID familyId, String reason);
}