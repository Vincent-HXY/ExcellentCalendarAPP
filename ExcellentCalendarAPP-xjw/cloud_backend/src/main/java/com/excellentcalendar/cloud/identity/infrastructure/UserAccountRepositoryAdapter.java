package com.excellentcalendar.cloud.identity.infrastructure;

import com.excellentcalendar.cloud.identity.domain.UserAccount;
import com.excellentcalendar.cloud.identity.domain.UserAccountRepository;
import com.excellentcalendar.cloud.identity.domain.UserAccountStatus;
import java.util.Optional;
import java.util.UUID;
import org.springframework.stereotype.Component;

/**
 * JPA adapter for the {@link UserAccountRepository} port.
 */
@Component
class UserAccountRepositoryAdapter implements UserAccountRepository {

    private final UserAccountJpaRepository jpaRepository;
    private final UserProfileJpaRepository profileJpaRepository;
    private final UserPreferencesJpaRepository preferencesJpaRepository;

    UserAccountRepositoryAdapter(
            UserAccountJpaRepository jpaRepository,
            UserProfileJpaRepository profileJpaRepository,
            UserPreferencesJpaRepository preferencesJpaRepository) {
        this.jpaRepository = jpaRepository;
        this.profileJpaRepository = profileJpaRepository;
        this.preferencesJpaRepository = preferencesJpaRepository;
    }

    @Override
    public void save(UserAccount account) {
        var entity = toEntity(account);
        jpaRepository.save(entity);
    }

    @Override
    public Optional<UserAccount> findById(UUID id) {
        return jpaRepository.findById(id).map(this::toDomain);
    }

    @Override
    public Optional<UserAccount> findByEmail(String email) {
        return jpaRepository.findByEmailIgnoreCase(email).map(this::toDomain);
    }

    @Override
    public boolean existsByEmail(String email) {
        return jpaRepository.existsByEmailIgnoreCase(email);
    }

    @Override
    public boolean existsByUsername(String username) {
        return profileJpaRepository.existsByUsernameIgnoreCase(username);
    }

    private UserAccountEntity toEntity(UserAccount domain) {
        var entity = new UserAccountEntity();
        entity.setId(domain.getId());
        entity.setEmail(domain.getEmail());
        entity.setPasswordHash(domain.getPasswordHash());
        entity.setStatus(domain.getStatus().name().toLowerCase());
        entity.setEmailVerifiedAt(domain.getEmailVerifiedAt());
        entity.setAgreementVersion(domain.getAgreementVersion());
        entity.setAgreementAccepted(domain.isAgreementAccepted());
        entity.setCreatedAt(domain.getCreatedAt());
        entity.setUpdatedAt(domain.getUpdatedAt());
        return entity;
    }

    private UserAccount toDomain(UserAccountEntity entity) {
        return new UserAccount(
                entity.getId(), entity.getEmail(), entity.getPasswordHash(),
                UserAccountStatus.valueOf(entity.getStatus().toUpperCase()),
                entity.getEmailVerifiedAt(), entity.getAgreementVersion(),
                entity.isAgreementAccepted(), entity.getCreatedAt(), entity.getUpdatedAt());
    }
}