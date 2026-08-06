package com.excellentcalendar.cloud.identity.domain;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * Port for persisting and loading verification challenges.
 */
public interface VerificationChallengeRepository {

    void save(VerificationChallenge challenge);

    Optional<VerificationChallenge> findById(UUID id);

    Optional<VerificationChallenge> findByIdAndUserId(UUID id, UUID userId);

    void expireAllForUser(UUID userId, String purpose);

    List<VerificationChallenge> findByUserIdAndPurpose(UUID userId, String purpose);
}