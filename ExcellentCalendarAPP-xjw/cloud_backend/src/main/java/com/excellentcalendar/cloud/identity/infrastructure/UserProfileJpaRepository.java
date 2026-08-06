package com.excellentcalendar.cloud.identity.infrastructure;

import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

public interface UserProfileJpaRepository extends JpaRepository<UserProfileEntity, UUID> {

    @Query("select case when count(p) > 0 then true else false end from UserProfileEntity p where lower(p.username) = lower(:username)")
    boolean existsByUsernameIgnoreCase(String username);

    Optional<UserProfileEntity> findByUserId(UUID userId);
}