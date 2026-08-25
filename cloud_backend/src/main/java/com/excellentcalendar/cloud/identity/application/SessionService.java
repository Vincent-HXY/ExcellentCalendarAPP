package com.excellentcalendar.cloud.identity.application;

import com.excellentcalendar.cloud.identity.application.support.AuthenticationAssembler;
import com.excellentcalendar.cloud.identity.application.support.ChallengeSupport;
import com.excellentcalendar.cloud.identity.application.support.SessionIssuer;
import com.excellentcalendar.cloud.identity.application.support.TimingEqualizer;
import com.excellentcalendar.cloud.identity.domain.EmailActionPurpose;
import com.excellentcalendar.cloud.identity.domain.NormalizedEmail;
import com.excellentcalendar.cloud.identity.domain.PasswordHasher;
import com.excellentcalendar.cloud.identity.domain.RateLimiter;
import com.excellentcalendar.cloud.identity.domain.SessionRevocationReason;
import com.excellentcalendar.cloud.identity.domain.TokenHash;
import com.excellentcalendar.cloud.identity.domain.UserAccountStatus;
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
import com.excellentcalendar.cloud.platform.api.ApiErrorContextResponse;
import com.excellentcalendar.cloud.platform.api.ApiException;
import java.time.Clock;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class SessionService {

    private final UserAccountRepository accountRepository;
    private final PasswordCredentialRepository credentialRepository;
    private final EmailActionChallengeRepository challengeRepository;
    private final UserSessionRepository sessionRepository;
    private final RefreshTokenGrantRepository grantRepository;
    private final SessionIssuer sessionIssuer;
    private final ChallengeSupport challengeSupport;
    private final AuthenticationAssembler authenticationAssembler;
    private final PasswordHasher passwordHasher;
    private final TimingEqualizer timingEqualizer;
    private final RateLimiter rateLimiter;
    private final RateLimitProperties rateLimitProperties;
    private final Clock clock;

    public SessionService(
            UserAccountRepository accountRepository,
            PasswordCredentialRepository credentialRepository,
            EmailActionChallengeRepository challengeRepository,
            UserSessionRepository sessionRepository,
            RefreshTokenGrantRepository grantRepository,
            SessionIssuer sessionIssuer,
            ChallengeSupport challengeSupport,
            AuthenticationAssembler authenticationAssembler,
            PasswordHasher passwordHasher,
            TimingEqualizer timingEqualizer,
            RateLimiter rateLimiter,
            RateLimitProperties rateLimitProperties,
            Clock clock) {
        this.accountRepository = accountRepository;
        this.credentialRepository = credentialRepository;
        this.challengeRepository = challengeRepository;
        this.sessionRepository = sessionRepository;
        this.grantRepository = grantRepository;
        this.sessionIssuer = sessionIssuer;
        this.challengeSupport = challengeSupport;
        this.authenticationAssembler = authenticationAssembler;
        this.passwordHasher = passwordHasher;
        this.timingEqualizer = timingEqualizer;
        this.rateLimiter = rateLimiter;
        this.rateLimitProperties = rateLimitProperties;
        this.clock = clock;
    }

    /**
     * noRollbackFor: the unverified-account branch must persist the fresh challenge it issues, and
     * the replay branch must persist the family revocation even though the response is an error.
     */
    @Transactional(noRollbackFor = ApiException.class)
    public AuthenticationResults.Authentication login(String clientIp, String email, String password) {
        NormalizedEmail normalizedEmail = NormalizedEmail.of(email);
        enforceRateLimit("login:" + clientIp + ":" + normalizedEmail.value(), loginRule());

        UserAccountEntity account = accountRepository.findByNormalizedEmail(normalizedEmail.value())
                .filter(candidate -> candidate.getStatus() != UserAccountStatus.deleted)
                .orElse(null);
        if (account == null) {
            timingEqualizer.burn(password);
            throw new ApiException(ApiErrorCode.AUTH_INVALID_CREDENTIALS);
        }
        PasswordCredentialEntity credential = credentialRepository.findById(account.getId()).orElse(null);
        if (credential == null || !passwordHasher.matches(password, credential.getPasswordHash())) {
            throw new ApiException(ApiErrorCode.AUTH_INVALID_CREDENTIALS);
        }
        return switch (account.getStatus()) {
            case active -> {
                SessionIssuer.IssuedSession issued = sessionIssuer.issueNewSession(account.getId());
                yield authenticationAssembler.assemble(
                        account, sessionIssuer.tokensFor(issued.session(), issued));
            }
            case pending_verification -> throw throwUnverified(account);
            case disabled -> throw new ApiException(ApiErrorCode.AUTH_ACCOUNT_DISABLED);
            case deleted -> throw new ApiException(ApiErrorCode.AUTH_INVALID_CREDENTIALS);
        };
    }

    /**
     * noRollbackFor: replay detection must persist the family revocation even though the response is
     * an error.
     */
    @Transactional(noRollbackFor = ApiException.class)
    public AuthenticationResults.TokenPair refresh(String refreshToken) {
        RefreshTokenGrantEntity grant = grantRepository.findWithLockingByTokenHash(TokenHash.of(refreshToken).hex())
                .orElseThrow(() -> new ApiException(ApiErrorCode.AUTH_REFRESH_TOKEN_INVALID));
        if (grant.isRevoked()) {
            throw new ApiException(ApiErrorCode.AUTH_REFRESH_TOKEN_INVALID);
        }
        if (!grant.getExpiresAt().isAfter(clock.instant())) {
            throw new ApiException(ApiErrorCode.AUTH_SESSION_EXPIRED);
        }
        UserSessionEntity session = sessionRepository.findById(grant.getSessionId())
                .orElseThrow(() -> new ApiException(ApiErrorCode.AUTH_SESSION_EXPIRED));
        if (session.isRevoked() || !session.getExpiresAt().isAfter(clock.instant())) {
            throw new ApiException(ApiErrorCode.AUTH_SESSION_EXPIRED);
        }
        requireActiveAccount(session.getUserId());
        if (grant.isConsumed()) {
            revokeFamily(session, SessionRevocationReason.refresh_token_reused);
            throw new ApiException(ApiErrorCode.AUTH_REFRESH_TOKEN_REUSED);
        }
        grant.consume(clock.instant());
        SessionIssuer.IssuedSession issued = sessionIssuer.issueChildGrant(session, grant.getId());
        return sessionIssuer.tokensFor(session, issued);
    }

    /**
     * Returns whether a revocation was actually performed: the contract's
     * {@code OperationResponse.performed} means "the requested operation was actually performed",
     * so an unknown/already-invalid token reports {@code false} while staying naturally idempotent.
     */
    @Transactional
    public boolean logout(String refreshToken) {
        RefreshTokenGrantEntity grant =
                grantRepository.findWithLockingByTokenHash(TokenHash.of(refreshToken).hex()).orElse(null);
        if (grant == null || grant.isRevoked()) {
            return false;
        }
        Optional<UserSessionEntity> session = sessionRepository.findById(grant.getSessionId())
                .filter(candidate -> !candidate.isRevoked());
        if (session.isEmpty()) {
            return false;
        }
        revokeFamily(session.get(), SessionRevocationReason.logout);
        return true;
    }

    @Transactional
    public void logoutAll(UUID accountId) {
        for (UserSessionEntity session : sessionRepository.findByUserIdAndRevokedAtIsNull(accountId)) {
            revokeFamily(session, SessionRevocationReason.logout_all);
        }
    }

    private UserAccountEntity requireActiveAccount(UUID accountId) {
        UserAccountEntity account = accountRepository.findById(accountId)
                .orElseThrow(() -> new ApiException(ApiErrorCode.AUTH_SESSION_EXPIRED));
        return switch (account.getStatus()) {
            case active -> account;
            // ADR-0004 §3: disabled AND deleted accounts both map to AUTH_ACCOUNT_DISABLED here.
            case disabled, deleted -> throw new ApiException(ApiErrorCode.AUTH_ACCOUNT_DISABLED);
            default -> throw new ApiException(ApiErrorCode.AUTH_SESSION_EXPIRED);
        };
    }

    private ApiException throwUnverified(UserAccountEntity account) {
        List<EmailActionChallengeEntity> active = challengeRepository
                .findActiveWithLockingByUserIdAndPurpose(account.getId(), EmailActionPurpose.registration_verification);
        EmailActionChallengeEntity challenge = active.isEmpty()
                ? challengeSupport.issue(
                        account.getId(), EmailActionPurpose.registration_verification, account.getEmail()).entity()
                : active.get(0);
        ApiErrorContextResponse.VerificationChallengeContextResponse context =
                new ApiErrorContextResponse.VerificationChallengeContextResponse(
                        challenge.getId().toString(),
                        EmailActionPurpose.registration_verification.wireValue(),
                        NormalizedEmail.of(challenge.getTargetEmail()).masked(),
                        List.of("code"),
                        challenge.getExpiresAt(),
                        challenge.getResendAvailableAt());
        return new ApiException(ApiErrorCode.AUTH_EMAIL_UNVERIFIED, new ApiErrorContextResponse(context));
    }

    private void revokeFamily(UserSessionEntity session, SessionRevocationReason reason) {
        session.revoke(clock.instant(), reason);
        sessionRepository.save(session);
        for (RefreshTokenGrantEntity grant : grantRepository.findBySessionId(session.getId())) {
            grant.revoke(clock.instant());
        }
    }

    private void enforceRateLimit(String key, RateLimiter.Rule rule) {
        RateLimiter.Result result = rateLimiter.tryAcquire(key, rule);
        if (!result.allowed()) {
            throw new ApiException(ApiErrorCode.API_RATE_LIMITED, result.retryAfterSeconds());
        }
    }

    private RateLimiter.Rule loginRule() {
        return new RateLimiter.Rule(
                rateLimitProperties.getLoginMaxPerWindow(), rateLimitProperties.getLoginWindowSeconds());
    }
}
