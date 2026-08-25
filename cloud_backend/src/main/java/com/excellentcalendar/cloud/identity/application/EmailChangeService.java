package com.excellentcalendar.cloud.identity.application;

import com.excellentcalendar.cloud.identity.application.support.AuthenticationAssembler;
import com.excellentcalendar.cloud.identity.application.support.ChallengeSupport;
import com.excellentcalendar.cloud.identity.application.support.PendingEmailChangeRequestPersister;
import com.excellentcalendar.cloud.identity.application.support.SessionIssuer;
import com.excellentcalendar.cloud.identity.domain.EmailActionPurpose;
import com.excellentcalendar.cloud.identity.domain.EmailChangeStatus;
import com.excellentcalendar.cloud.identity.domain.NormalizedEmail;
import com.excellentcalendar.cloud.identity.domain.PasswordHasher;
import com.excellentcalendar.cloud.identity.domain.RateLimiter;
import com.excellentcalendar.cloud.identity.domain.SessionRevocationReason;
import com.excellentcalendar.cloud.identity.domain.UserAccountStatus;
import com.excellentcalendar.cloud.identity.domain.VerificationCredentialType;
import com.excellentcalendar.cloud.identity.infrastructure.RateLimitProperties;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.EmailActionChallengeEntity;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.EmailActionChallengeRepository;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.EmailChangeRequestEntity;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.EmailChangeRequestRepository;
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
import java.util.List;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Email change workflow: request against the old inbox with password ownership proof, confirm with
 * the code sent to the new inbox. The original email stays the only login email while pending.
 */
@Service
public class EmailChangeService {

    private final UserAccountRepository accountRepository;
    private final PasswordCredentialRepository credentialRepository;
    private final EmailActionChallengeRepository challengeRepository;
    private final EmailChangeRequestRepository requestRepository;
    private final UserSessionRepository sessionRepository;
    private final RefreshTokenGrantRepository grantRepository;
    private final ChallengeSupport challengeSupport;
    private final SessionIssuer sessionIssuer;
    private final AuthenticationAssembler authenticationAssembler;
    private final PasswordHasher passwordHasher;
    private final PendingEmailChangeRequestPersister persister;
    private final RateLimiter rateLimiter;
    private final RateLimitProperties rateLimitProperties;
    private final Clock clock;

    public EmailChangeService(
            UserAccountRepository accountRepository,
            PasswordCredentialRepository credentialRepository,
            EmailActionChallengeRepository challengeRepository,
            EmailChangeRequestRepository requestRepository,
            UserSessionRepository sessionRepository,
            RefreshTokenGrantRepository grantRepository,
            ChallengeSupport challengeSupport,
            SessionIssuer sessionIssuer,
            AuthenticationAssembler authenticationAssembler,
            PasswordHasher passwordHasher,
            PendingEmailChangeRequestPersister persister,
            RateLimiter rateLimiter,
            RateLimitProperties rateLimitProperties,
            Clock clock) {
        this.accountRepository = accountRepository;
        this.credentialRepository = credentialRepository;
        this.challengeRepository = challengeRepository;
        this.requestRepository = requestRepository;
        this.sessionRepository = sessionRepository;
        this.grantRepository = grantRepository;
        this.challengeSupport = challengeSupport;
        this.sessionIssuer = sessionIssuer;
        this.authenticationAssembler = authenticationAssembler;
        this.passwordHasher = passwordHasher;
        this.persister = persister;
        this.rateLimiter = rateLimiter;
        this.rateLimitProperties = rateLimitProperties;
        this.clock = clock;
    }

    @Transactional
    public AuthenticationResults.Challenge requestChange(UUID accountId, String newEmail, String currentPassword) {
        enforceRateLimit("challenge:" + accountId, challengeRule());
        UserAccountEntity account = requireActiveAccount(accountId);
        PasswordCredentialEntity credential = credentialRepository.findById(accountId)
                .orElseThrow(() -> new ApiException(ApiErrorCode.API_INTERNAL_ERROR));
        if (!passwordHasher.matches(currentPassword, credential.getPasswordHash())) {
            throw new ApiException(ApiErrorCode.AUTH_CURRENT_PASSWORD_INVALID);
        }
        NormalizedEmail normalizedNew = NormalizedEmail.of(newEmail);
        if (normalizedNew.value().equals(account.getNormalizedEmail())) {
            // AUTH_EMAIL_ALREADY_EXISTS would be misleading: the email belongs to this account.
            throw new ApiException(ApiErrorCode.API_VALIDATION_FAILED,
                    List.of(new ApiFieldErrorResponse(
                            "new_email", ApiErrorCode.API_VALIDATION_FAILED.code(),
                            "new_email must differ from the current email")));
        }
        if (accountRepository.findByNormalizedEmail(normalizedNew.value())
                .filter(candidate -> !candidate.getId().equals(accountId)
                        && candidate.getStatus() != UserAccountStatus.deleted)
                .isPresent()) {
            throw new ApiException(ApiErrorCode.AUTH_EMAIL_ALREADY_EXISTS);
        }

        // One pending request per user (partial unique index): supersede the previous one.
        // The persister runs in its own transaction and retries once on the concurrency race.
        return persister.persist(accountId, account.getEmail(), newEmail.trim());
    }

    /**
     * noRollbackFor: failed attempts and the max-attempts invalidation must persist even though the
     * response is an error.
     */
    @Transactional(noRollbackFor = ApiException.class)
    public AuthenticationResults.Authentication confirmChange(
            UUID accountId, UUID sessionId, UUID requestId, VerificationCredentialType credentialType, String code) {
        enforceRateLimit("challenge:" + accountId, challengeRule());
        UserAccountEntity account = requireActiveAccount(accountId);
        EmailChangeRequestEntity request = requestRepository.findWithLockingById(requestId)
                .orElseThrow(() -> new ApiException(ApiErrorCode.AUTH_VERIFICATION_INVALID));
        if (!request.getUserId().equals(accountId)) {
            throw new ApiException(ApiErrorCode.AUTH_VERIFICATION_INVALID);
        }
        switch (request.getStatus()) {
            case verified -> throw new ApiException(ApiErrorCode.AUTH_VERIFICATION_USED);
            case expired -> throw new ApiException(ApiErrorCode.AUTH_VERIFICATION_EXPIRED);
            case cancelled -> throw new ApiException(ApiErrorCode.AUTH_VERIFICATION_INVALID);
            case pending -> {
            }
        }
        if (!request.getExpiresAt().isAfter(clock.instant())) {
            request.markExpired(clock.instant());
            throw new ApiException(ApiErrorCode.AUTH_VERIFICATION_EXPIRED);
        }
        EmailActionChallengeEntity challenge = challengeRepository.findWithLockingById(request.getChallengeId())
                .orElseThrow(() -> new ApiException(ApiErrorCode.AUTH_VERIFICATION_INVALID));
        if (challenge.isConsumed()) {
            throw new ApiException(ApiErrorCode.AUTH_VERIFICATION_USED);
        }
        if (challenge.isInvalidated()) {
            throw new ApiException(ApiErrorCode.AUTH_VERIFICATION_INVALID);
        }
        if (!challenge.getExpiresAt().isAfter(clock.instant())) {
            throw new ApiException(ApiErrorCode.AUTH_VERIFICATION_EXPIRED);
        }
        // The new inbox may have been taken while the challenge was pending: check BEFORE the
        // code check consumes the one-time challenge (noRollbackFor would persist the burn).
        NormalizedEmail normalizedNew = NormalizedEmail.of(request.getNewEmail());
        if (accountRepository.findByNormalizedEmail(normalizedNew.value())
                .filter(candidate -> !candidate.getId().equals(accountId)
                        && candidate.getStatus() != UserAccountStatus.deleted)
                .isPresent()) {
            throw new ApiException(ApiErrorCode.AUTH_EMAIL_ALREADY_EXISTS);
        }
        if (credentialType != VerificationCredentialType.CODE
                || !challengeSupport.verifyCode(challenge, code, clock.instant())) {
            throw new ApiException(ApiErrorCode.AUTH_VERIFICATION_INVALID);
        }

        account.replaceEmail(request.getNewEmail(), normalizedNew.value(), clock.instant());
        accountRepository.save(account);
        request.complete(clock.instant());
        requestRepository.save(request);

        // rotate_current_and_revoke_others.
        revokeOtherSessions(accountId, sessionId, SessionRevocationReason.email_changed);
        UserSessionEntity currentSession = sessionRepository.findById(sessionId)
                .orElseThrow(() -> new ApiException(ApiErrorCode.AUTH_SESSION_EXPIRED));
        SessionIssuer.IssuedSession issued = sessionIssuer.rotateSessionGrants(currentSession);
        return authenticationAssembler.assemble(account, sessionIssuer.tokensFor(currentSession, issued));
    }

    private UserAccountEntity requireActiveAccount(UUID accountId) {
        UserAccountEntity account = accountRepository.findById(accountId)
                .orElseThrow(() -> new ApiException(ApiErrorCode.AUTH_SESSION_EXPIRED));
        return switch (account.getStatus()) {
            case active -> account;
            case disabled -> throw new ApiException(ApiErrorCode.AUTH_ACCOUNT_DISABLED);
            default -> throw new ApiException(ApiErrorCode.AUTH_SESSION_EXPIRED);
        };
    }

    private void revokeOtherSessions(UUID accountId, UUID currentSessionId, SessionRevocationReason reason) {
        List<UserSessionEntity> others = sessionRepository.findByUserIdAndRevokedAtIsNull(accountId).stream()
                .filter(session -> !session.getId().equals(currentSessionId))
                .toList();
        for (UserSessionEntity session : others) {
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

    private RateLimiter.Rule challengeRule() {
        return new RateLimiter.Rule(
                rateLimitProperties.getChallengeMaxPerWindow(), rateLimitProperties.getChallengeWindowSeconds());
    }
}
