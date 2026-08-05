package com.excellentcalendar.cloud.userdevice.repository;

import com.excellentcalendar.cloud.userdevice.model.UserProfile;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface UserProfileRepository extends JpaRepository<UserProfile, UUID> {

    boolean existsByUsernameIgnoreCase(String username);
}