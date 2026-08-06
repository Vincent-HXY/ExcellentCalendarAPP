package com.excellentcalendar.cloud.identity.application;

import com.excellentcalendar.cloud.identity.domain.RefreshTokenGrant;
import com.excellentcalendar.cloud.identity.domain.RefreshTokenGrantRepository;
import com.excellentcalendar.cloud.identity.domain.UserAccount;
import com.excellentcalendar.cloud.identity.domain.UserAccountRepository;
import com.excellentcalendar.cloud.identity.domain.VerificationChallenge;
import com.excellentcalendar.cloud.identity.domain.VerificationChallengeRepository;
import com.excellentcalendar.cloud.identity.infrastructure.UserProfileEntity;
import com.excellentcalendar.cloud.identity.infrastructure.UserProfileJpaRepository;
import com.excellentcalendar.cloud.identity.infrastructure.UserPreferencesEntity;
import com.excellentcalendar.cloud.identity.infrastructure.UserPreferencesJpaRepository;
import com.excellentcalendar.cloud.platform.jwt.JwtTokenService;
import com.excellentcalendar.cloud.platform.password.AuthErrors;
import com.excellentcalendar.cloud.platform.password.HashUtils;
import java.time.Clock;
import java.time.Instant;
import java.util.UUID;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Use case: verify a registration email and create the authenticated session.
 */
@Component
public class VerifyRegistrationUseCase {

    private static final long REFRESH_TOKEN_TTL_SECONDS = 2592000; // 30 days

    private final UserAccountRepository userAccountRepository;
    private final VerificationChallengeRepository challengeRepository;
    private final RefreshTokenGrantRepository grantRepository;
    private final UserProfileJpaRepository profileJpaRepository;
    private final UserPreferencesJpaRepository preferencesJpaRepository;
    private final JwtTokenService jwtTokenService;
    private final Clock clock;

    public VerifyRegistrationUseCase(
            UserAccountRepository userAccountRepository,
            VerificationChallengeRepository challengeRepository,
            RefreshTokenGrantRepository grantRepository,
            UserProfileJpaRepository profileJpaRepository,
            UserPreferencesJpaRepository preferencesJpaRepository,
            JwtTokenService jwtTokenService,
            Clock clock) {
        this.userAccountRepository = userAccountRepository;
        this.challengeRepository = challengeRepository;
        this.grantRepository = grantRepository;
        this.profileJpaRepository = profileJpaRepository;
        this.preferencesJpaRepository = preferencesJpaRepository;
        this.jwtTokenService = jwtTokenService;
        this.clock = clock;
    }

    @Transactional
    public AuthenticationResult verify(UUID challengeId, String credentialType, String code) {
        VerificationChallenge challenge = challengeRepository.findById(challengeId)
                .orElseThrow(AuthErrors::verificationInvalid);

        if (!"registration_verification".equals(challenge.getPurpose())) {
            throw AuthErrors.verificationInvalid();
        }

        if (challenge.isConsumed()) {
            throw AuthErrors.verificationUsed();
        }

        if (challenge.isExpired(clock)) {
            throw AuthErrors.verificationExpired();
        }

        // Verify the code
        String codeHash = HashUtils.sha256(code);
        if (!codeHash.equals(challenge.getCodeHash())) {
            challenge.recordFailedAttempt();
            challengeRepository.save(challenge);
            throw AuthErrors.verificationInvalid();
        }

        // Consume the challenge
        challenge.consume();
        challengeRepository.save(challenge);

        // Activate the account
        UserAccount account = userAccountRepository.findById(challenge.getUserId())
                .orElseThrow(AuthErrors::verificationInvalid);
        account.verifyEmail(clock);
        userAccountRepository.save(account);

        // Create tokens
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
                true);
    }
}