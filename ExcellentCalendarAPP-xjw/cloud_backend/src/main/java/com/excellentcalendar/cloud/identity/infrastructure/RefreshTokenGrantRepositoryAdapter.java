package com.excellentcalendar.cloud.identity.infrastructure;

import com.excellentcalendar.cloud.identity.domain.RefreshTokenGrant;
import com.excellentcalendar.cloud.identity.domain.RefreshTokenGrantRepository;
import com.excellentcalendar.cloud.identity.domain.RefreshTokenGrantStatus;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Collectors;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * JPA adapter for the {@link RefreshTokenGrantRepository} port.
 */
@Component
class RefreshTokenGrantRepositoryAdapter implements RefreshTokenGrantRepository {

    private final RefreshTokenGrantJpaRepository jpaRepository;

    RefreshTokenGrantRepositoryAdapter(RefreshTokenGrantJpaRepository jpaRepository) {
        this.jpaRepository = jpaRepository;
    }

    @Override
    public void save(RefreshTokenGrant grant) {
        jpaRepository.save(toEntity(grant));
    }

    @Override
    public Optional<RefreshTokenGrant> findByTokenHash(String tokenHash) {
        return jpaRepository.findByTokenHash(tokenHash).map(this::toDomain);
    }

    @Override
    public List<RefreshTokenGrant> findByFamilyId(UUID familyId) {
        return jpaRepository.findByFamilyId(familyId).stream()
                .map(this::toDomain)
                .collect(Collectors.toList());
    }

    @Override
    public List<RefreshTokenGrant> findByUserId(UUID userId) {
        return jpaRepository.findByUserId(userId).stream()
                .map(this::toDomain)
                .collect(Collectors.toList());
    }

    @Override
    public List<RefreshTokenGrant> findActiveByUserId(UUID userId) {
        return jpaRepository.findActiveByUserId(userId).stream()
                .map(this::toDomain)
                .collect(Collectors.toList());
    }

    @Override
    @Transactional
    public void revokeAllForUser(UUID userId, String reason) {
        jpaRepository.revokeAllActiveByUserId(userId, reason);
    }

    @Override
    @Transactional
    public void revokeAllByFamilyId(UUID familyId, String reason) {
        jpaRepository.revokeAllByFamilyId(familyId, reason);
    }

    private RefreshTokenGrantEntity toEntity(RefreshTokenGrant domain) {
        var entity = new RefreshTokenGrantEntity();
        entity.setId(domain.getId());
        entity.setUserId(domain.getUserId());
        entity.setSessionId(domain.getSessionId());
        entity.setTokenHash(domain.getTokenHash());
        entity.setFamilyId(domain.getFamilyId());
        entity.setParentId(domain.getParentId());
        entity.setStatus(domain.getStatus().name());
        entity.setExpiresAt(domain.getExpiresAt());
        entity.setRevokedAt(domain.getRevokedAt());
        entity.setRevocationReason(domain.getRevocationReason());
        entity.setCreatedAt(domain.getCreatedAt());
        return entity;
    }

    private RefreshTokenGrant toDomain(RefreshTokenGrantEntity entity) {
        return new RefreshTokenGrant(
                entity.getId(), entity.getUserId(), entity.getSessionId(),
                entity.getTokenHash(), entity.getFamilyId(), entity.getParentId(),
                RefreshTokenGrantStatus.valueOf(entity.getStatus()),
                entity.getExpiresAt(), entity.getRevokedAt(),
                entity.getRevocationReason(), entity.getCreatedAt());
    }
}