package com.excellentcalendar.cloud.identity.application;

import com.excellentcalendar.cloud.identity.domain.RefreshTokenGrant;
import com.excellentcalendar.cloud.identity.domain.RefreshTokenGrantRepository;
import com.excellentcalendar.cloud.platform.password.AuthErrors;
import com.excellentcalendar.cloud.platform.password.HashUtils;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Use case: revoke a single session (logout).
 */
@Component
public class LogoutUseCase {

    private final RefreshTokenGrantRepository grantRepository;

    public LogoutUseCase(RefreshTokenGrantRepository grantRepository) {
        this.grantRepository = grantRepository;
    }

    @Transactional
    public void logout(String refreshToken) {
        String tokenHash = HashUtils.sha256(refreshToken);
        RefreshTokenGrant grant = grantRepository.findByTokenHash(tokenHash)
                .orElse(null);
        if (grant == null) return; // idempotent

        grant.revoke("logout", java.time.Clock.systemUTC());
        grantRepository.save(grant);
    }
}