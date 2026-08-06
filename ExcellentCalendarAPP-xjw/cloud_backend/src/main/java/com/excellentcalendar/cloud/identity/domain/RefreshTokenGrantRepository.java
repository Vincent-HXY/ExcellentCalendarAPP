package com.excellentcalendar.cloud.identity.domain;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * Port for persisting and loading refresh token grants.
 */
public interface RefreshTokenGrantRepository {

    void save(RefreshTokenGrant grant);

    Optional<RefreshTokenGrant> findByTokenHash(String tokenHash);

    List<RefreshTokenGrant> findByFamilyId(UUID familyId);

    List<RefreshTokenGrant> findByUserId(UUID userId);

    List<RefreshTokenGrant> findActiveByUserId(UUID userId);

    void revokeAllForUser(UUID userId, String reason);

    void revokeAllByFamilyId(UUID familyId, String reason);
}