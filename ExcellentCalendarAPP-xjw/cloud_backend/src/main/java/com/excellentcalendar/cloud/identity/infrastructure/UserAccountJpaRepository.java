package com.excellentcalendar.cloud.identity.infrastructure;

import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

interface UserAccountJpaRepository extends JpaRepository<UserAccountEntity, UUID> {

    @Query("select u from UserAccountEntity u where lower(u.email) = lower(:email)")
    Optional<UserAccountEntity> findByEmailIgnoreCase(String email);

    @Query("select case when count(u) > 0 then true else false end from UserAccountEntity u where lower(u.email) = lower(:email)")
    boolean existsByEmailIgnoreCase(String email);
}