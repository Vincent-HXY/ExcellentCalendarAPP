package com.excellentcalendar.cloud.identity.application;

import com.excellentcalendar.cloud.identity.domain.EmailChangeRequest;
import com.excellentcalendar.cloud.identity.domain.EmailChangeRequestRepository;
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
import com.excellentcalendar.cloud.platform.mail.EmailSender;
import com.excellentcalendar.cloud.platform.password.AuthErrors;
import com.excellentcalendar.cloud.platform.password.HashUtils;
import java.time.Clock;
import java.time.Instant;
import java.util.UUID;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Use case: confirm an email change by verifying the challenge credential.
 */
@Component
public class EmailChangeConfirmUseCase {

    private static final long REFRESH_TOKEN_TTL_SECONDS = 2592000; // 30 days

    private final UserAccountRepository userAccountRepository;
    private final EmailChangeRequestRepository emailChangeRequestRepository;
    private final VerificationChallengeRepository challengeRepository;
    private final RefreshTokenGrantRepository grantRepository;
    private final UserProfileJpaRepository profileJpaRepository;
    private final UserPreferencesJpaRepository preferencesJpaRepository;
    private final JwtTokenService jwtTokenService;
    private final EmailSender emailSender;
    private final Clock clock;

    public EmailChangeConfirmUseCase(
            UserAccountRepository userAccountRepository,
            EmailChangeRequestRepository emailChangeRequestRepository,
            VerificationChallengeRepository challengeRepository,
            RefreshTokenGrantRepository grantRepository,
            UserProfileJpaRepository profileJpaRepository,
            UserPreferencesJpaRepository preferencesJpaRepository,
            JwtTokenService jwtTokenService,
            EmailSender emailSender,
            Clock clock) {
        this.userAccountRepository = userAccountRepository;
        this.emailChangeRequestRepository = emailChangeRequestRepository;
        this.challengeRepository = challengeRepository;
        this.grantRepository = grantRepository;
        this.profileJpaRepository = profileJpaRepository;
        this.preferencesJpaRepository = preferencesJpaRepository;
        this.jwtTokenService = jwtTokenService;
        this.emailSender = emailSender;
        this.clock = clock;
    }

    @Transactional
    public AuthenticationResult confirmEmailChange(
            UUID userId, UUID emailChangeRequestId, UUID challengeId,
            String credentialType, String code) {

        // Verify the challenge
        VerificationChallenge challenge = challengeRepository.findByIdAndUserId(challengeId, userId)
                .orElseThrow(AuthErrors::verificationInvalid);

        if (challenge.isConsumed()) {
            throw AuthErrors.verificationUsed();
        }

        if (challenge.isExpired(clock)) {
            throw AuthErrors.verificationExpired();
        }

        String codeHash = HashUtils.sha256(code);
        if (!codeHash.equals(challenge.getCodeHash())) {
            challenge.recordFailedAttempt();
            challengeRepository.save(challenge);
            throw AuthErrors.verificationInvalid();
        }

        // Consume the challenge
        challenge.consume();
        challengeRepository.save(challenge);

        // Verify the email change request
        EmailChangeRequest emailChangeRequest = emailChangeRequestRepository
                .findByIdAndUserId(emailChangeRequestId, userId)
                .orElseThrow(AuthErrors::verificationInvalid);

        if (!emailChangeRequest.isPending()) {
            throw AuthErrors.verificationUsed();
        }

        if (emailChangeRequest.isExpired(clock)) {
            emailChangeRequest.markExpired();
            emailChangeRequestRepository.save(emailChangeRequest);
            throw AuthErrors.verificationExpired();
        }

        // Check the new email hasn't been taken by another user
        if (userAccountRepository.existsByEmail(emailChangeRequest.getNewEmail())) {
            throw AuthErrors.emailAlreadyExists();
        }

        // Mark the request as verified
        emailChangeRequest.markVerified(clock);
        emailChangeRequestRepository.save(emailChangeRequest);

        // Update the account's email
        UserAccount account = userAccountRepository.findById(userId)
                .orElseThrow(AuthErrors::sessionExpired);

        String oldEmail = account.getEmail();
        account.changeEmail(emailChangeRequest.getNewEmail(), clock);
        userAccountRepository.save(account);

        // Revoke all sessions except the current one
        grantRepository.revokeAllForUser(account.getId(), "email_changed");

        // Create new session and tokens
        UUID sessionId = UUID.randomUUID();
        String accessToken = jwtTokenService.createAccessToken(account.getId(), sessionId);
        Instant accessTokenExpiresAt = clock.instant().plusSeconds(900);

        String refreshTokenRaw = HashUtils.generateToken();
        String refreshTokenHash = HashUtils.sha256(refreshTokenRaw);
        Instant refreshTokenExpiresAt = clock.instant().plusSeconds(REFRESH_TOKEN_TTL_SECONDS);

        RefreshTokenGrant newGrant = RefreshTokenGrant.createRoot(
                account.getId(), sessionId, refreshTokenHash, refreshTokenExpiresAt);
        grantRepository.save(newGrant);

        // Notify the old email
        emailSender.sendEmailChangedNotification(oldEmail);

        // Get profile data
        UserProfileEntity profile = profileJpaRepository.findByUserId(account.getId()).orElse(null);

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