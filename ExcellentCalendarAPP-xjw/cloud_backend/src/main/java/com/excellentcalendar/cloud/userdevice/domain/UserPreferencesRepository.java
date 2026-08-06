package com.excellentcalendar.cloud.userdevice.domain;

import java.util.Optional;
import java.util.UUID;

/**
 * Port for persisting and loading user preferences.
 */
public interface UserPreferencesRepository {

    void save(UserPreferences preferences);

    Optional<UserPreferences> findByUserId(UUID userId);
}