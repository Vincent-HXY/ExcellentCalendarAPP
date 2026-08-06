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
 * Use case: authenticate a user with email and password.
 */
@Component
public class LoginUseCase {

    private static final long REFRESH_TOKEN_TTL_SECONDS = 2592000; // 30 days

    private final UserAccountRepository userAccountRepository;
    private final RefreshTokenGrantRepository grantRepository;
    private final UserProfileJpaRepository profileJpaRepository;
    private final UserPreferencesJpaRepository preferencesJpaRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtTokenService jwtTokenService;
    private final Clock clock;

    public LoginUseCase(
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
    public AuthenticationResult login(String email, String password) {
        UserAccount account = userAccountRepository.findByEmail(email)
                .orElseThrow(AuthErrors::invalidCredentials);

        // Verify password
        if (!passwordEncoder.matches(password, account.getPasswordHash())) {
            throw AuthErrors.invalidCredentials();
        }

        // Check account status
        if (account.isDisabled()) {
            throw AuthErrors.accountDisabled();
        }

        if (!account.isEmailVerified()) {
            throw AuthErrors.emailUnverified();
        }

        // Create session and tokens
        UUID sessionId = UUID.randomUUID();
        String accessToken = jwtTokenService.createAccessToken(account.getId(), sessionId);
        Instant accessTokenExpiresAt = clock.instant().plusSeconds(900);

        String refreshTokenRaw = HashUtils.generateToken();
        String refreshTokenHash = HashUtils.sha256(refreshTokenRaw);
        Instant refreshTokenExpiresAt = clock.instant().plusSeconds(REFRESH_TOKEN_TTL_SECONDS);

        RefreshTokenGrant grant = RefreshTokenGrant.createRoot(
                account.getId(), sessionId, refreshTokenHash, refreshTokenExpiresAt);
        grantRepository.save(grant);

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
                sessionId,
                account.isEmailVerified());
    }
}