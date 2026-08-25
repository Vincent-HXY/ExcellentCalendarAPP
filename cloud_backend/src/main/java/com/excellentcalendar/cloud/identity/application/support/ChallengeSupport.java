package com.excellentcalendar.cloud.identity.application.support;

import com.excellentcalendar.cloud.identity.application.AuthenticationResults;
import com.excellentcalendar.cloud.identity.domain.EmailActionPurpose;
import com.excellentcalendar.cloud.identity.domain.MailSender;
import com.excellentcalendar.cloud.identity.domain.TokenHash;
import com.excellentcalendar.cloud.identity.domain.VerificationCodeGenerator;
import com.excellentcalendar.cloud.identity.infrastructure.IdentityProperties;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.EmailActionChallengeEntity;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.EmailActionChallengeRepository;
import com.excellentcalendar.cloud.platform.time.IdGenerator;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * Creates email challenges and verifies codes against them. Mail leaves after the surrounding
 * transaction commits, so a rolled-back registration never emails anyone.
 */
@Component
public class ChallengeSupport {

    private final EmailActionChallengeRepository challengeRepository;
    private final VerificationCodeGenerator codeGenerator;
    private final MailSender mailSender;
    private final IdentityProperties properties;
    private final Clock clock;
    private final IdGenerator idGenerator;

    public ChallengeSupport(
            EmailActionChallengeRepository challengeRepository,
            VerificationCodeGenerator codeGenerator,
            MailSender mailSender,
            IdentityProperties properties,
            Clock clock,
            IdGenerator idGenerator) {
        this.challengeRepository = challengeRepository;
        this.codeGenerator = codeGenerator;
        this.mailSender = mailSender;
        this.properties = properties;
        this.clock = clock;
        this.idGenerator = idGenerator;
    }

    public record IssuedChallenge(EmailActionChallengeEntity entity, String code) {
    }

    /**
     * Invalidates previous active challenges of the same purpose and creates a new one with a fresh
     * 6-digit code. The code is emailed after commit.
     */
    public IssuedChallenge issue(UUID userId, EmailActionPurpose purpose, String targetEmail) {
        Instant now = clock.instant();
        challengeRepository.invalidateActiveByUserAndPurpose(userId, purpose, now);
        String code = codeGenerator.generate();
        Duration ttl = Duration.ofSeconds(ttlSeconds(purpose));
        EmailActionChallengeEntity entity = new EmailActionChallengeEntity(
                idGenerator.next(),
                userId,
                purpose,
                targetEmail,
                TokenHash.of(code).hex(),
                properties.getMaxAttempts(),
                now.plus(ttl),
                now.plusSeconds(properties.getResendIntervalSeconds()),
                now);
        challengeRepository.save(entity);
        afterCommit(() -> mailSender.sendVerificationCode(targetEmail, purpose, code));
        return new IssuedChallenge(entity, code);
    }

    public AuthenticationResults.Challenge toChallengeResult(
            EmailActionChallengeEntity challenge, UUID actionId) {
        return new AuthenticationResults.Challenge(
                challenge.getId(),
                actionId,
                challenge.getPurpose(),
                mask(challenge.getTargetEmail()),
                List.of("code"),
                challenge.getExpiresAt(),
                challenge.getResendAvailableAt());
    }

    /**
     * Verifies a 6-digit code against a locked challenge. Returns true on success (challenge
     * consumed); records a failed attempt otherwise and invalidates the challenge at maxAttempts.
     */
    public boolean verifyCode(EmailActionChallengeEntity challenge, String code, Instant now) {
        if (challenge.isConsumed() || challenge.isInvalidated()) {
            return false;
        }
        if (challenge.getCodeHash() == null
                || !TokenHash.constantTimeEquals(TokenHash.of(code).hex(), challenge.getCodeHash())) {
            challenge.recordFailedAttempt(now);
            return false;
        }
        challenge.consume(now);
        return true;
    }

    private long ttlSeconds(EmailActionPurpose purpose) {
        return switch (purpose) {
            case registration_verification, email_change -> properties.getRegistrationTtlSeconds();
            case password_reset -> properties.getPasswordResetTtlSeconds();
        };
    }

    private String mask(String email) {
        return com.excellentcalendar.cloud.identity.domain.NormalizedEmail.of(email).masked();
    }

    private void afterCommit(Runnable action) {
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    action.run();
                }
            });
        } else {
            action.run();
        }
    }
}
