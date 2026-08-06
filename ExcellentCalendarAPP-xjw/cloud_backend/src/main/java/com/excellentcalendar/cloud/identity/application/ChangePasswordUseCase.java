package com.excellentcalendar.cloud.identity.application;

import com.excellentcalendar.cloud.identity.domain.RefreshTokenGrant;
import com.excellentcalendar.cloud.identity.domain.RefreshTokenGrantRepository;
import com.excellentcalendar.cloud.identity.domain.UserAccount;
import com.excellentcalendar.cloud.identity.domain.UserAccountRepository;
import com.excellentcalendar.cloud.identity.infrastructure.UserProfileEntity;
import com.excellentcalendar.cloud.identity.infrastructure.UserProfileJpaRepository;
import com.excellentcalendar.cloud.identity.infrastructure.UserPreferencesEntity;
import com.excellentcalendar.cloud.identity.infrastructure.UserPreferencesJpaRepository;
import com.excellentcalendar.cloud.platform.jwt.JwtTokenService;
import com.excellentcalendar.cloud.platform.password.AuthErrors;
import com.excellentcalendar.cloud.platform.password.HashUtils;
import com.excellentcalendar.cloud.platform.password.PasswordEncoder;
import java.time.Clock;
import java.time.Instant;
import java.util.UUID;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Use case: change the authenticated user's password.
 * Revokes other sessions and rotates the current one.
 */
@Component
public class ChangePasswordUseCase {

    private static final long REFRESH_TOKEN_TTL_SECONDS = 2592000; // 30 days

    private final UserAccountRepository userAccountRepository;
    private final RefreshTokenGrantRepository grantRepository;
    private final UserProfileJpaRepository profileJpaRepository;
    private final UserPreferencesJpaRepository preferencesJpaRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtTokenService jwtTokenService;
    private final Clock clock;

    public ChangePasswordUseCase(
            UserAccountRepository userAccountRepository,
            RefreshTokenGrantRepository grantRepository,
            UserProfileJpaRepository profileJpaRepository,
            UserPreferencesJpaRepository preferencesJpaRepository,
            PasswordEncoder passwordEncoder,
            JwtTokenService jwtTokenService,
            Clock clock) {
        this.userAccountRepository = userAccountRepository;
        this.grantRepository = grantRepository;
        this.profileJpaRepository = profileJpaRepository;
        this.preferencesJpaRepository = preferencesJpaRepository;
        this.passwordEncoder = passwordEncoder;
        this.jwtTokenService = jwtTokenService;
        this.clock = clock;
    }

    @Transactional
    public AuthenticationResult changePassword(
            UUID userId, UUID currentSessionId,
            String currentPassword, String newPassword) {

        UserAccount account = userAccountRepository.findById(userId)
                .orElseThrow(AuthErrors::sessionExpired);

        if (account.isDisabled()) {
            throw AuthErrors.accountDisabled();
        }

        // Verify current password
        if (!passwordEncoder.matches(currentPassword, account.getPasswordHash())) {
            throw AuthErrors.currentPasswordInvalid();
        }

        // Check new password is different
        if (passwordEncoder.matches(newPassword, account.getPasswordHash())) {
            throw AuthErrors.passwordUnchanged();
        }

        // Check password policy
        if (newPassword.length() < 8 || newPassword.length() > 128) {
            throw AuthErrors.passwordPolicyViolation();
        }

        // Revoke all other sessions
        var activeGrants = grantRepository.findActiveByUserId(userId);
        for (var grant : activeGrants) {
            if (!grant.getSessionId().equals(currentSessionId)) {
                grant.revoke("password_changed", clock);
                grantRepository.save(grant);
            }
        }

        // Update password
        String newPasswordHash = passwordEncoder.encode(newPassword);
        account.updatePassword(newPasswordHash, clock);
        userAccountRepository.save(account);

        // Create new token pair for the current session
        String accessToken = jwtTokenService.createAccessToken(account.getId(), currentSessionId);
        Instant accessTokenExpiresAt = clock.instant().plusSeconds(900);

        String refreshTokenRaw = HashUtils.generateToken();
        String refreshTokenHash = HashUtils.sha256(refreshTokenRaw);
        Instant refreshTokenExpiresAt = clock.instant().plusSeconds(REFRESH_TOKEN_TTL_SECONDS);

        // Create a new root grant for the new token family
        RefreshTokenGrant newGrant = RefreshTokenGrant.createRoot(
                account.getId(), currentSessionId, refreshTokenHash, refreshTokenExpiresAt);
        grantRepository.save(newGrant);

        // Get profile data
        UserProfileEntity profile = profileJpaRepository.findByUserId(account.getId()).orElse(null);
        UserPreferencesEntity prefs = preferencesJpaRepository.findByUserId(account.getId()).orElse(null);

        return new AuthenticationResult(
                account.getId(),
                account.getEmail(),
                profile != null ? profile.getUsername() : "",
                profile != null ? profile.getDisplayName() : "",
                accessToken,
                accessTokenExpiresAt,
                refreshTokenRaw,
                refreshTokenExpiresAt,
                currentSessionId,
                account.isEmailVerified());
    }
}