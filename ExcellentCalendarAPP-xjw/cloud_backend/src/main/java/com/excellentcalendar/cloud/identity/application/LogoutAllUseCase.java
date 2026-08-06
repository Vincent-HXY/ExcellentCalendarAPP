package com.excellentcalendar.cloud.identity.application;

import com.excellentcalendar.cloud.identity.domain.RefreshTokenGrantRepository;
import java.util.UUID;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Use case: revoke all sessions for a user (logout all devices).
 */
@Component
public class LogoutAllUseCase {

    private final RefreshTokenGrantRepository grantRepository;

    public LogoutAllUseCase(RefreshTokenGrantRepository grantRepository) {
        this.grantRepository = grantRepository;
    }

    @Transactional
    public void logoutAll(UUID userId) {
        grantRepository.revokeAllForUser(userId, "logout_all");
    }
}