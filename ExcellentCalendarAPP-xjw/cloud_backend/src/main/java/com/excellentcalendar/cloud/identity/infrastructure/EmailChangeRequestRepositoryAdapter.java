package com.excellentcalendar.cloud.identity.infrastructure;

import com.excellentcalendar.cloud.identity.domain.EmailChangeRequest;
import com.excellentcalendar.cloud.identity.domain.EmailChangeRequestRepository;
import com.excellentcalendar.cloud.identity.domain.EmailChangeRequestStatus;
import java.util.Optional;
import java.util.UUID;
import org.springframework.stereotype.Component;

/**
 * JPA adapter for the {@link EmailChangeRequestRepository} port.
 */
@Component
class EmailChangeRequestRepositoryAdapter implements EmailChangeRequestRepository {

    private final EmailChangeRequestJpaRepository jpaRepository;

    EmailChangeRequestRepositoryAdapter(EmailChangeRequestJpaRepository jpaRepository) {
        this.jpaRepository = jpaRepository;
    }

    @Override
    public void save(EmailChangeRequest request) {
        jpaRepository.save(toEntity(request));
    }

    @Override
    public Optional<EmailChangeRequest> findById(UUID id) {
        return jpaRepository.findById(id).map(this::toDomain);
    }

    @Override
    public Optional<EmailChangeRequest> findByIdAndUserId(UUID id, UUID userId) {
        return jpaRepository.findByIdAndUserId(id, userId).map(this::toDomain);
    }

    private EmailChangeRequestEntity toEntity(EmailChangeRequest domain) {
        var entity = new EmailChangeRequestEntity();
        entity.setId(domain.getId());
        entity.setUserId(domain.getUserId());
        entity.setOldEmail(domain.getOldEmail());
        entity.setNewEmail(domain.getNewEmail());
        entity.setChallengeId(domain.getChallengeId());
        entity.setStatus(domain.getStatus().name());
        entity.setExpiresAt(domain.getExpiresAt());
        entity.setCreatedAt(domain.getCreatedAt());
        entity.setUpdatedAt(domain.getUpdatedAt());
        return entity;
    }

    private EmailChangeRequest toDomain(EmailChangeRequestEntity entity) {
        return new EmailChangeRequest(
                entity.getId(), entity.getUserId(), entity.getOldEmail(),
                entity.getNewEmail(), entity.getChallengeId(),
                EmailChangeRequestStatus.valueOf(entity.getStatus()),
                entity.getExpiresAt(), entity.getCreatedAt(), entity.getUpdatedAt());
    }
}