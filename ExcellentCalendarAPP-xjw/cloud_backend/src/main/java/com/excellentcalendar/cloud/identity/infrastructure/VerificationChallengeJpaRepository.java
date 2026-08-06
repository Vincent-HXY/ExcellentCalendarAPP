package com.excellentcalendar.cloud.identity.infrastructure;

import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

interface VerificationChallengeJpaRepository extends JpaRepository<VerificationChallengeEntity, UUID> {

    List<VerificationChallengeEntity> findByUserIdAndPurpose(UUID userId, String purpose);
}