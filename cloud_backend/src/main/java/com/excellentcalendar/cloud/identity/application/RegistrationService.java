package com.excellentcalendar.cloud.identity.application;

import com.excellentcalendar.cloud.identity.application.support.AuthenticationAssembler;
import com.excellentcalendar.cloud.identity.application.support.ChallengeSupport;
import com.excellentcalendar.cloud.identity.application.support.SessionIssuer;
import com.excellentcalendar.cloud.identity.domain.EmailActionPurpose;
import com.excellentcalendar.cloud.identity.domain.NormalizedEmail;
import com.excellentcalendar.cloud.identity.domain.PasswordHasher;
import com.excellentcalendar.cloud.identity.domain.PasswordPolicy;
import com.excellentcalendar.cloud.identity.domain.RateLimiter;
import com.excellentcalendar.cloud.identity.domain.UserAccountStatus;
import com.excellentcalendar.cloud.identity.domain.VerificationCredentialType;
import com.excellentcalendar.cloud.identity.infrastructure.RateLimitProperties;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.EmailActionChallengeEntity;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.EmailActionChallengeRepository;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.PasswordCredentialEntity;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.PasswordCredentialRepository;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.UserAccountEntity;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.UserAccountRepository;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.UserAgreementAcceptanceEntity;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.UserAgreementAcceptanceRepository;
import com.excellentcalendar.cloud.platform.api.ApiErrorCode;
import com.excellentcalendar.cloud.platform.api.ApiException;
import com.excellentcalendar.cloud.platform.api.ApiFieldErrorResponse;
import com.excellentcalendar.cloud.platform.time.IdGenerator;
import com.excellentcalendar.cloud.userdevice.application.ProfileService;
import java.time.Clock;
import java.util.List;
import java.util.UUID;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class RegistrationService {

    private final UserAccountRepository accountRepository;
    private final PasswordCredentialRepository credentialRepository;
    private final UserAgreementAcceptanceRepository agreementRepository;
    private final EmailActionChallengeRepository challengeRepository;
    private final ProfileService profileService;
    private final ChallengeSupport challengeSupport;
    private final SessionIssuer sessionIssuer;
    private final AuthenticationAssembler authenticationAssembler;
    private final PasswordHasher passwordHasher;
    private final RateLimiter rateLimiter;
    private final RateLimitProperties rateLimitProperties;
    private final Clock clock;
    private final IdGenerator idGenerator;

    public RegistrationService(
            UserAccountRepository accountRepository,
            PasswordCredentialRepository credentialRepository,
            UserAgreementAcceptanceRepository agreementRepository,
            EmailActionChallengeRepository challengeRepository,
            ProfileService profileService,
            ChallengeSupport challengeSupport,
            SessionIssuer sessionIssuer,
            AuthenticationAssembler authenticationAssembler,
            PasswordHasher passwordHasher,
            RateLimiter rateLimiter,
            RateLimitProperties rateLimitProperties,
            Clock clock,
            IdGenerator idGenerator) {
        this.accountRepository = accountRepository;
        this.credentialRepository = credentialRepository;
        this.agreementRepository = agreementRepository;
        this.challengeRepository = challengeRepository;
        this.profileService = profileService;
        this.challengeSupport = challengeSupport;
        this.sessionIssuer = sessionIssuer;
        this.authenticationAssembler = authenticationAssembler;
        this.passwordHasher = passwordHasher;
        this.rateLimiter = rateLimiter;
        this.rateLimitProperties = rateLimitProperties;
        this.clock = clock;
        this.idGenerator = idGenerator;
    }

    @Transactional
    public AuthenticationResults.RegistrationPending register(
            String clientIp,
            String email,
            String username,
            String displayName,
            String password,
            String locale,
            String timezone,
            String agreementVersion) {
        enforceRateLimit("register:" + clientIp, registerRule());
        try {
            PasswordPolicy.validate(password);
        } catch (PasswordPolicy.PasswordPolicyViolationException exception) {
            throw new ApiException(ApiErrorCode.AUTH_PASSWORD_POLICY_VIOLATION,
                    List.of(new ApiFieldErrorResponse(
                            "password", ApiErrorCode.AUTH_PASSWORD_POLICY_VIOLATION.code(),
                            "Password does not meet the active password policy")));
        }
        String normalizedTimezone = com.excellentcalendar.cloud.platform.time.IanaTimezones
                .tryNormalize(timezone)
                .orElseThrow(() -> new ApiException(ApiErrorCode.API_VALIDATION_FAILED,
                        List.of(new ApiFieldErrorResponse(
                                "timezone", ApiErrorCode.API_VALIDATION_FAILED.code(),
                                "timezone must be a valid IANA timezone id"))));

        NormalizedEmail normalizedEmail = NormalizedEmail.of(email);
        UUID accountId = idGenerator.next();
        UserAccountEntity account = new UserAccountEntity(
                accountId,
                email.trim(),
                normalizedEmail.value(),
                UserAccountStatus.pending_verification,
                clock.instant());
        PasswordCredentialEntity credential = new PasswordCredentialEntity(
                accountId, passwordHasher.hash(password), clock.instant());

        try {
            accountRepository.saveAndFlush(account);
            credentialRepository.save(credential);
            profileService.createProfile(accountId, username, displayName);
            profileService.createPreferences(accountId, locale, normalizedTimezone);
            agreementRepository.save(new UserAgreementAcceptanceEntity(
                    idGenerator.next(), accountId, agreementVersion, clock.instant()));
        } catch (DataIntegrityViolationException exception) {
            throw mapIntegrityViolation(exception);
        }

        ChallengeSupport.IssuedChallenge issued =
                challengeSupport.issue(accountId, EmailActionPurpose.registration_verification, account.getEmail());
        AuthenticationResults.Challenge challenge = challengeSupport.toChallengeResult(issued.entity(), null);
        return new AuthenticationResults.RegistrationPending(accountId, challenge);
    }

    @Transactional(noRollbackFor = ApiException.class)
    public AuthenticationResults.Challenge resend(String clientIp, UUID challengeId) {
        enforceRateLimit("challenge:" + clientIp, challengeRule());
        EmailActionChallengeEntity challenge = challengeRepository.findWithLockingById(challengeId)
                .orElseThrow(() -> new ApiException(ApiErrorCode.AUTH_VERIFICATION_INVALID));
        if (challenge.getPurpose() != EmailActionPurpose.registration_verification) {
            throw new ApiException(ApiErrorCode.AUTH_VERIFICATION_INVALID);
        }
        UserAccountEntity account = requireAccountForChallenge(challenge);
        if (account.getStatus() == UserAccountStatus.disabled) {
            // Contract declares AUTH_ACCOUNT_DISABLED for resend: disabled accounts must not
            // receive verification mail.
            throw new ApiException(ApiErrorCode.AUTH_ACCOUNT_DISABLED);
        }
        rejectUnavailableForResend(challenge);
        if (clock.instant().isBefore(challenge.getResendAvailableAt())) {
            long retryAfter = Math.max(1, java.time.Duration.between(
                    clock.instant(), challenge.getResendAvailableAt()).toSeconds() + 1);
            throw new ApiException(ApiErrorCode.API_RATE_LIMITED, (int) retryAfter);
        }
        challenge.invalidate(clock.instant());
        ChallengeSupport.IssuedChallenge issued = challengeSupport.issue(
                account.getId(), EmailActionPurpose.registration_verification, challenge.getTargetEmail());
        return challengeSupport.toChallengeResult(issued.entity(), null);
    }

    /**
     * noRollbackFor: failed attempts and the max-attempts invalidation must persist even though the
     * response is an error, otherwise the counter would reset on every wrong code.
     */
    @Transactional(noRollbackFor = ApiException.class)
    public AuthenticationResults.Authentication verify(
            String clientIp, UUID challengeId, VerificationCredentialType credentialType, String code) {
        enforceRateLimit("challenge:" + clientIp, challengeRule());
        EmailActionChallengeEntity challenge = challengeRepository.findWithLockingById(challengeId)
                .orElseThrow(() -> new ApiException(ApiErrorCode.AUTH_VERIFICATION_INVALID));
        if (challenge.getPurpose() != EmailActionPurpose.registration_verification) {
            throw new ApiException(ApiErrorCode.AUTH_VERIFICATION_INVALID);
        }
        UserAccountEntity account = requireAccountForChallenge(challenge);
        rejectFinishedChallenge(challenge);
        if (account.getStatus() == UserAccountStatus.disabled) {
            throw new ApiException(ApiErrorCode.AUTH_ACCOUNT_DISABLED);
        }
        if (account.getStatus() != UserAccountStatus.pending_verification) {
            throw new ApiException(ApiErrorCode.AUTH_VERIFICATION_INVALID);
        }
        if (credentialType != VerificationCredentialType.CODE) {
            // link tokens are not issued in this phase; only codes can validate a challenge.
            throw new ApiException(ApiErrorCode.AUTH_VERIFICATION_INVALID);
        }
        if (!challengeSupport.verifyCode(challenge, code, clock.instant())) {
            // Includes the attempts-exceeded branch: the challenge is invalidated at maxAttempts.
            throw new ApiException(ApiErrorCode.AUTH_VERIFICATION_INVALID);
        }
        account.activate(clock.instant());
        accountRepository.save(account);
        SessionIssuer.IssuedSession issued = sessionIssuer.issueNewSession(account.getId());
        AuthenticationResults.TokenPair tokens = sessionIssuer.tokensFor(issued.session(), issued);
        return authenticationAssembler.assemble(account, tokens);
    }

    private UserAccountEntity requireAccountForChallenge(EmailActionChallengeEntity challenge) {
        return accountRepository.findById(challenge.getUserId())
                .filter(account -> account.getStatus() != UserAccountStatus.deleted)
                .orElseThrow(() -> new ApiException(ApiErrorCode.AUTH_VERIFICATION_INVALID));
    }

    private void rejectFinishedChallenge(EmailActionChallengeEntity challenge) {
        rejectUnavailableForResend(challenge);
        if (!challenge.getExpiresAt().isAfter(clock.instant())) {
            throw new ApiException(ApiErrorCode.AUTH_VERIFICATION_EXPIRED);
        }
    }

    private void rejectUnavailableForResend(EmailActionChallengeEntity challenge) {
        if (challenge.isConsumed()) {
            throw new ApiException(ApiErrorCode.AUTH_VERIFICATION_USED);
        }
        if (challenge.isInvalidated()) {
            throw new ApiException(ApiErrorCode.AUTH_VERIFICATION_INVALID);
        }
    }

    private ApiException mapIntegrityViolation(DataIntegrityViolationException exception) {
        String message = String.valueOf(exception.getMostSpecificCause().getMessage());
        if (message.contains("uq_user_accounts_normalized_email")) {
            return new ApiException(ApiErrorCode.AUTH_EMAIL_ALREADY_EXISTS,
                    List.of(new ApiFieldErrorResponse(
                            "email", ApiErrorCode.AUTH_EMAIL_ALREADY_EXISTS.code(),
                            "The email is already associated with an account")));
        }
        if (message.contains("uq_user_profiles_normalized_username")) {
            return new ApiException(ApiErrorCode.AUTH_USERNAME_ALREADY_EXISTS,
                    List.of(new ApiFieldErrorResponse(
                            "username", ApiErrorCode.AUTH_USERNAME_ALREADY_EXISTS.code(),
                            "The username is already in use")));
        }
        return new ApiException(ApiErrorCode.API_INTERNAL_ERROR);
    }

    private void enforceRateLimit(String key, RateLimiter.Rule rule) {
        RateLimiter.Result result = rateLimiter.tryAcquire(key, rule);
        if (!result.allowed()) {
            throw new ApiException(ApiErrorCode.API_RATE_LIMITED, result.retryAfterSeconds());
        }
    }

    private RateLimiter.Rule registerRule() {
        return new RateLimiter.Rule(
                rateLimitProperties.getRegisterMaxPerWindow(), rateLimitProperties.getRegisterWindowSeconds());
    }

    private RateLimiter.Rule challengeRule() {
        return new RateLimiter.Rule(
                rateLimitProperties.getChallengeMaxPerWindow(), rateLimitProperties.getChallengeWindowSeconds());
    }
}
