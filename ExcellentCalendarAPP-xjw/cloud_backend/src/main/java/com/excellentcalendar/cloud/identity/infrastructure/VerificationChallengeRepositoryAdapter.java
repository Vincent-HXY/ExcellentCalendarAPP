package com.excellentcalendar.cloud.identity.infrastructure;

import com.excellentcalendar.cloud.identity.domain.VerificationChallenge;
import com.excellentcalendar.cloud.identity.domain.VerificationChallengeRepository;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Collectors;
import org.springframework.stereotype.Component;

/**
 * JPA adapter for the {@link VerificationChallengeRepository} port.
 */
@Component
class VerificationChallengeRepositoryAdapter implements VerificationChallengeRepository {

    private final VerificationChallengeJpaRepository jpaRepository;

    VerificationChallengeRepositoryAdapter(VerificationChallengeJpaRepository jpaRepository) {
        this.jpaRepository = jpaRepository;
    }

    @Override
    public void save(VerificationChallenge challenge) {
        jpaRepository.save(toEntity(challenge));
    }

    @Override
    public Optional<VerificationChallenge> findById(UUID id) {
        return jpaRepository.findById(id).map(this::toDomain);
    }

    @Override
    public Optional<VerificationChallenge> findByIdAndUserId(UUID id, UUID userId) {
        return jpaRepository.findById(id)
                .filter(e -> e.getUserId().equals(userId))
                .map(this::toDomain);
    }

    @Override
    public void expireAllForUser(UUID userId, String purpose) {
        jpaRepository.findByUserIdAndPurpose(userId, purpose).stream()
                .filter(e -> e.getConsumedAt() == null)
                .forEach(e -> {
                    e.setExpiresAt(java.time.Instant.now());
                    jpaRepository.save(e);
                });
    }

    @Override
    public List<VerificationChallenge> findByUserIdAndPurpose(UUID userId, String purpose) {
        return jpaRepository.findByUserIdAndPurpose(userId, purpose).stream()
                .map(this::toDomain)
                .collect(Collectors.toList());
    }

    private VerificationChallengeEntity toEntity(VerificationChallenge domain) {
        var entity = new VerificationChallengeEntity();
        entity.setId(domain.getId());
        entity.setUserId(domain.getUserId());
        entity.setPurpose(domain.getPurpose());
        entity.setMaskedEmail(domain.getMaskedEmail());
        entity.setCredentialTypes(domain.getCredentialTypes());
        entity.setCodeHash(domain.getCodeHash());
        entity.setLinkTokenHash(domain.getLinkTokenHash());
        entity.setExpiresAt(domain.getExpiresAt());
        entity.setFailedAttempts(domain.getFailedAttempts());
        entity.setMaxAttempts(domain.getMaxAttempts());
        entity.setConsumedAt(domain.getConsumedAt());
        entity.setCreatedAt(domain.getCreatedAt());
        return entity;
    }

    private VerificationChallenge toDomain(VerificationChallengeEntity entity) {
        return new VerificationChallenge(
                entity.getId(), entity.getUserId(), entity.getPurpose(),
                entity.getMaskedEmail(), entity.getCredentialTypes(),
                entity.getCodeHash(), entity.getLinkTokenHash(),
                entity.getExpiresAt(), entity.getMaxAttempts(),
                entity.getFailedAttempts(), entity.getConsumedAt(),
                entity.getCreatedAt());
    }
}