package com.excellentcalendar.cloud.identity.application;

import com.excellentcalendar.cloud.identity.application.support.AuthenticationAssembler;
import com.excellentcalendar.cloud.identity.application.support.ChallengeSupport;
import com.excellentcalendar.cloud.identity.application.support.SessionIssuer;
import com.excellentcalendar.cloud.identity.application.support.TimingEqualizer;
import com.excellentcalendar.cloud.identity.domain.EmailActionPurpose;
import com.excellentcalendar.cloud.identity.domain.NormalizedEmail;
import com.excellentcalendar.cloud.identity.domain.PasswordHasher;
import com.excellentcalendar.cloud.identity.domain.PasswordPolicy;
import com.excellentcalendar.cloud.identity.domain.RateLimiter;
import com.excellentcalendar.cloud.identity.domain.SessionRevocationReason;
import com.excellentcalendar.cloud.identity.domain.UserAccountStatus;
import com.excellentcalendar.cloud.identity.domain.VerificationCredentialType;
import com.excellentcalendar.cloud.identity.infrastructure.IdentityProperties;
import com.excellentcalendar.cloud.identity.infrastructure.RateLimitProperties;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.EmailActionChallengeEntity;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.EmailActionChallengeRepository;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.PasswordCredentialEntity;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.PasswordCredentialRepository;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.RefreshTokenGrantEntity;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.RefreshTokenGrantRepository;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.UserAccountEntity;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.UserAccountRepository;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.UserSessionEntity;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.UserSessionRepository;
import com.excellentcalendar.cloud.platform.api.ApiErrorCode;
import com.excellentcalendar.cloud.platform.api.ApiException;
import com.excellentcalendar.cloud.platform.api.ApiFieldErrorResponse;
import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class PasswordService {

    private final UserAccountRepository accountRepository;
    private final PasswordCredentialRepository credentialRepository;
    private final EmailActionChallengeRepository challengeRepository;
    private final UserSessionRepository sessionRepository;
    private final RefreshTokenGrantRepository grantRepository;
    private final ChallengeSupport challengeSupport;
    private final SessionIssuer sessionIssuer;
    private final AuthenticationAssembler authenticationAssembler;
    private final PasswordHasher passwordHasher;
    private final TimingEqualizer timingEqualizer;
    private final RateLimiter rateLimiter;
    private final RateLimitProperties rateLimitProperties;
    private final IdentityProperties properties;
    private final Clock clock;

    public PasswordService(
            UserAccountRepository accountRepository,
            PasswordCredentialRepository credentialRepository,
            EmailActionChallengeRepository challengeRepository,
            UserSessionRepository sessionRepository,
            RefreshTokenGrantRepository grantRepository,
            ChallengeSupport challengeSupport,
            SessionIssuer sessionIssuer,
            AuthenticationAssembler authenticationAssembler,
            PasswordHasher passwordHasher,
            TimingEqualizer timingEqualizer,
            RateLimiter rateLimiter,
            RateLimitProperties rateLimitProperties,
            IdentityProperties properties,
            Clock clock) {
        this.accountRepository = accountRepository;
        this.credentialRepository = credentialRepository;
        this.challengeRepository = challengeRepository;
        this.sessionRepository = sessionRepository;
        this.grantRepository = grantRepository;
        this.challengeSupport = challengeSupport;
        this.sessionIssuer = sessionIssuer;
        this.authenticationAssembler = authenticationAssembler;
        this.passwordHasher = passwordHasher;
        this.timingEqualizer = timingEqualizer;
        this.rateLimiter = rateLimiter;
        this.rateLimitProperties = rateLimitProperties;
        this.properties = properties;
        this.clock = clock;
    }

    /**
     * Identical public result for registered and unknown emails; never reveals account existence.
     * The unknown-email branch burns a dummy Argon2 match so response timing stays comparable.
     */
    @Transactional
    public AuthenticationResults.PasswordResetDispatch requestReset(String clientIp, String email) {
        enforceRateLimit("password-reset:" + clientIp, resetRule());
        NormalizedEmail normalizedEmail = NormalizedEmail.of(email);
        Instant now = clock.instant();
        accountRepository.findByNormalizedEmail(normalizedEmail.value())
                .filter(account -> account.getStatus() != UserAccountStatus.deleted)
                .ifPresentOrElse(
                        account -> challengeSupport.issue(
                                account.getId(), EmailActionPurpose.password_reset, account.getEmail()),
                        () -> timingEqualizer.burn(email));
        // Unknown email: same success shape, with a resend hint equal to the resend interval.
        return new AuthenticationResults.PasswordResetDispatch(
                now.plusSeconds(properties.getResendIntervalSeconds()));
    }

    /**
     * noRollbackFor: failed attempts and the max-attempts invalidation must persist even though the
     * response is an error.
     */
    @Transactional(noRollbackFor = ApiException.class)
    public void confirmReset(
            String clientIp,
            String email,
            VerificationCredentialType credentialType,
            String code,
            String newPassword) {
        enforceRateLimit("challenge:" + clientIp, challengeRule());
        NormalizedEmail normalizedEmail = NormalizedEmail.of(email);
        UserAccountEntity account = accountRepository.findByNormalizedEmail(normalizedEmail.value())
                .filter(candidate -> candidate.getStatus() != UserAccountStatus.deleted)
                .orElseThrow(() -> new ApiException(ApiErrorCode.AUTH_VERIFICATION_INVALID));
        if (account.getStatus() == UserAccountStatus.disabled) {
            throw new ApiException(ApiErrorCode.AUTH_ACCOUNT_DISABLED);
        }
        if (account.getStatus() != UserAccountStatus.active) {
            throw new ApiException(ApiErrorCode.AUTH_VERIFICATION_INVALID);
        }
        EmailActionChallengeEntity challenge = challengeRepository
                .findLatestWithLockingByUserIdAndPurpose(account.getId(), EmailActionPurpose.password_reset)
                .stream().findFirst()
                .orElseThrow(() -> new ApiException(ApiErrorCode.AUTH_VERIFICATION_INVALID));
        rejectFinishedChallenge(challenge);
        // Validate the new password BEFORE consuming the one-time challenge: a policy violation
        // must not burn the code (noRollbackFor would otherwise persist the consumption).
        validateNewPassword(newPassword);
        if (credentialType != VerificationCredentialType.CODE
                || !challengeSupport.verifyCode(challenge, code, clock.instant())) {
            throw new ApiException(ApiErrorCode.AUTH_VERIFICATION_INVALID);
        }
        PasswordCredentialEntity credential = credentialRepository.findById(account.getId())
                .orElseThrow(() -> new ApiException(ApiErrorCode.API_INTERNAL_ERROR));
        credential.replaceHash(passwordHasher.hash(newPassword), clock.instant());
        revokeAllSessions(account.getId(), SessionRevocationReason.password_reset);
    }

    @Transactional
    public AuthenticationResults.Authentication change(
            UUID accountId, UUID sessionId, String currentPassword, String newPassword) {
        enforceRateLimit("challenge:" + accountId, challengeRule());
        UserAccountEntity account = accountRepository.findById(accountId)
                .filter(candidate -> candidate.getStatus() != UserAccountStatus.deleted)
                .orElseThrow(() -> new ApiException(ApiErrorCode.AUTH_SESSION_EXPIRED));
        if (account.getStatus() == UserAccountStatus.disabled) {
            throw new ApiException(ApiErrorCode.AUTH_ACCOUNT_DISABLED);
        }
        PasswordCredentialEntity credential = credentialRepository.findById(accountId)
                .orElseThrow(() -> new ApiException(ApiErrorCode.API_INTERNAL_ERROR));
        if (!passwordHasher.matches(currentPassword, credential.getPasswordHash())) {
            throw new ApiException(ApiErrorCode.AUTH_CURRENT_PASSWORD_INVALID);
        }
        if (passwordHasher.matches(newPassword, credential.getPasswordHash())) {
            throw new ApiException(ApiErrorCode.AUTH_PASSWORD_UNCHANGED);
        }
        validateNewPassword(newPassword);
        credential.replaceHash(passwordHasher.hash(newPassword), clock.instant());

        // rotate_current_and_revoke_others: other devices lose access, the current one keeps going.
        revokeOtherSessions(accountId, sessionId, SessionRevocationReason.password_changed);
        UserSessionEntity currentSession = sessionRepository.findById(sessionId)
                .orElseThrow(() -> new ApiException(ApiErrorCode.AUTH_SESSION_EXPIRED));
        SessionIssuer.IssuedSession issued = sessionIssuer.rotateSessionGrants(currentSession);
        return authenticationAssembler.assemble(account, sessionIssuer.tokensFor(currentSession, issued));
    }

    private void validateNewPassword(String newPassword) {
        try {
            PasswordPolicy.validate(newPassword);
        } catch (PasswordPolicy.PasswordPolicyViolationException exception) {
            throw new ApiException(ApiErrorCode.AUTH_PASSWORD_POLICY_VIOLATION,
                    List.of(new ApiFieldErrorResponse(
                            "new_password", ApiErrorCode.AUTH_PASSWORD_POLICY_VIOLATION.code(),
                            "Password does not meet the active password policy")));
        }
    }

    private void rejectFinishedChallenge(EmailActionChallengeEntity challenge) {
        if (challenge.isConsumed()) {
            throw new ApiException(ApiErrorCode.AUTH_VERIFICATION_USED);
        }
        if (challenge.isInvalidated()) {
            throw new ApiException(ApiErrorCode.AUTH_VERIFICATION_INVALID);
        }
        if (!challenge.getExpiresAt().isAfter(clock.instant())) {
            throw new ApiException(ApiErrorCode.AUTH_VERIFICATION_EXPIRED);
        }
    }

    private void revokeAllSessions(UUID accountId, SessionRevocationReason reason) {
        revokeSessions(sessionRepository.findByUserIdAndRevokedAtIsNull(accountId), reason);
    }

    private void revokeOtherSessions(UUID accountId, UUID currentSessionId, SessionRevocationReason reason) {
        revokeSessions(
                sessionRepository.findByUserIdAndRevokedAtIsNull(accountId).stream()
                        .filter(session -> !session.getId().equals(currentSessionId))
                        .toList(),
                reason);
    }

    private void revokeSessions(List<UserSessionEntity> sessions, SessionRevocationReason reason) {
        for (UserSessionEntity session : sessions) {
            session.revoke(clock.instant(), reason);
            sessionRepository.save(session);
            for (RefreshTokenGrantEntity grant : grantRepository.findBySessionId(session.getId())) {
                grant.revoke(clock.instant());
            }
        }
    }

    private void enforceRateLimit(String key, RateLimiter.Rule rule) {
        RateLimiter.Result result = rateLimiter.tryAcquire(key, rule);
        if (!result.allowed()) {
            throw new ApiException(ApiErrorCode.API_RATE_LIMITED, result.retryAfterSeconds());
        }
    }

    private RateLimiter.Rule resetRule() {
        return new RateLimiter.Rule(
                rateLimitProperties.getPasswordResetMaxPerWindow(),
                rateLimitProperties.getPasswordResetWindowSeconds());
    }

    private RateLimiter.Rule challengeRule() {
        return new RateLimiter.Rule(
                rateLimitProperties.getChallengeMaxPerWindow(), rateLimitProperties.getChallengeWindowSeconds());
    }
}
