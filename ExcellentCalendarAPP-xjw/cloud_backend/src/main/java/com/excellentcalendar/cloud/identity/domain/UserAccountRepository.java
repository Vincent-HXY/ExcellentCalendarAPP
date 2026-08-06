package com.excellentcalendar.cloud.identity.domain;

import java.util.Optional;
import java.util.UUID;

/**
 * Port for persisting and loading user accounts.
 */
public interface UserAccountRepository {

    void save(UserAccount account);

    Optional<UserAccount> findById(UUID id);

    Optional<UserAccount> findByEmail(String email);

    boolean existsByEmail(String email);

    boolean existsByUsername(String username);
}