package com.excellentcalendar.cloud.userdevice.domain;

import java.util.Optional;
import java.util.UUID;

/**
 * Port for persisting and loading user profiles.
 */
public interface UserProfileRepository {

    void save(UserProfile profile);

    Optional<UserProfile> findByUserId(UUID userId);

    boolean existsByUsername(String username);
}