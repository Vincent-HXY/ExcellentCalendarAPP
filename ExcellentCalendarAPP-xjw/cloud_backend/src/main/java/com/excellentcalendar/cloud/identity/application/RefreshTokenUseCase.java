package com.excellentcalendar.cloud.identity.application;

import com.excellentcalendar.cloud.identity.domain.RefreshTokenGrant;
import com.excellentcalendar.cloud.identity.domain.RefreshTokenGrantRepository;
import com.excellentcalendar.cloud.identity.domain.UserAccount;
import com.excellentcalendar.cloud.identity.domain.UserAccountRepository;
import com.excellentcalendar.cloud.platform.jwt.JwtTokenService;
import com.excellentcalendar.cloud.platform.password.AuthErrors;
import com.excellentcalendar.cloud.platform.password.HashUtils;
import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Use case: rotate a refresh token and return a new token pair.
 */
@Component
public class RefreshTokenUseCase {

    private static final long REFRESH_TOKEN_TTL_SECONDS = 2592000; // 30 days

    private final UserAccountRepository userAccountRepository;
    private final RefreshTokenGrantRepository grantRepository;
    private final JwtTokenService jwtTokenService;
    private final Clock clock;

    public RefreshTokenUseCase(
            UserAccountRepository userAccountRepository,
            RefreshTokenGrantRepository grantRepository,
            JwtTokenService jwtTokenService,
            Clock clock) {
        this.userAccountRepository = userAccountRepository;
        this.grantRepository = grantRepository;
        this.jwtTokenService = jwtTokenService;
        this.clock = clock;
    }

    @Transactional
    public AuthenticationResult.TokenPair refresh(String refreshToken) {
        String tokenHash = HashUtils.sha256(refreshToken);
        RefreshTokenGrant currentGrant = grantRepository.findByTokenHash(tokenHash)
                .orElseThrow(AuthErrors::refreshTokenInvalid);

        // Check if the token has been reused (already consumed)
        if (currentGrant.isConsumed()) {
            // Revoke the entire family
            grantRepository.revokeAllByFamilyId(currentGrant.getFamilyId(), "refresh_token_reused");
            throw AuthErrors.refreshTokenReused();
        }

        if (currentGrant.isRevoked()) {
            throw AuthErrors.refreshTokenInvalid();
        }

        if (currentGrant.isExpired(clock)) {
            currentGrant.markExpired();
            grantRepository.save(currentGrant);
            throw AuthErrors.sessionExpired();
        }

        // Check account status
        UserAccount account = userAccountRepository.findById(currentGrant.getUserId())
                .orElseThrow(AuthErrors::refreshTokenInvalid);

        if (account.isDisabled()) {
            throw AuthErrors.accountDisabled();
        }

        // Atomically consume the current grant
        currentGrant.consume();
        grantRepository.save(currentGrant);

        // Create a new child grant
        UUID sessionId = currentGrant.getSessionId();
        String newAccessToken = jwtTokenService.createAccessToken(account.getId(), sessionId);
        Instant accessTokenExpiresAt = clock.instant().plusSeconds(900);

        String newRefreshTokenRaw = HashUtils.generateToken();
        String newRefreshTokenHash = HashUtils.sha256(newRefreshTokenRaw);
        Instant refreshTokenExpiresAt = clock.instant().plusSeconds(REFRESH_TOKEN_TTL_SECONDS);

        RefreshTokenGrant newGrant = RefreshTokenGrant.createChild(
                account.getId(), sessionId, newRefreshTokenHash,
                currentGrant.getFamilyId(), currentGrant.getId(),
                refreshTokenExpiresAt);
        grantRepository.save(newGrant);

        return new AuthenticationResult.TokenPair(
                newAccessToken, accessTokenExpiresAt,
                newRefreshTokenRaw, refreshTokenExpiresAt, sessionId);
    }
}