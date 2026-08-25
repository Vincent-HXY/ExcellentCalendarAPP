package com.excellentcalendar.cloud.media.infrastructure.persistence;

import java.util.Optional;
import java.util.UUID;
import org.springframework.data.repository.Repository;

public interface UserAvatarAssetRepository extends Repository<UserAvatarAssetEntity, UUID> {

    UserAvatarAssetEntity save(UserAvatarAssetEntity entity);

    Optional<UserAvatarAssetEntity> findById(UUID id);
}
