package com.excellentcalendar.cloud.identity.application;

import com.excellentcalendar.cloud.identity.domain.UserAccount;
import com.excellentcalendar.cloud.identity.domain.UserAccountRepository;
import com.excellentcalendar.cloud.identity.domain.VerificationChallenge;
import com.excellentcalendar.cloud.identity.domain.VerificationChallengeRepository;
import com.excellentcalendar.cloud.platform.mail.EmailSender;
import com.excellentcalendar.cloud.platform.password.AuthErrors;
import com.excellentcalendar.cloud.platform.password.HashUtils;
import java.time.Clock;
import java.time.Instant;
import java.util.UUID;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Use case: resend a registration verification code.
 */
@Component
public class ResendVerificationUseCase {

    private final UserAccountRepository userAccountRepository;
    private final VerificationChallengeRepository challengeRepository;
    private final EmailSender emailSender;
    private final Clock clock;

    public ResendVerificationUseCase(
            UserAccountRepository userAccountRepository,
            VerificationChallengeRepository challengeRepository,
            EmailSender emailSender,
            Clock clock) {
        this.userAccountRepository = userAccountRepository;
        this.challengeRepository = challengeRepository;
        this.emailSender = emailSender;
        this.clock = clock;
    }

    @Transactional
    public ResendResult resend(UUID challengeId) {
        VerificationChallenge oldChallenge = challengeRepository.findById(challengeId)
                .orElseThrow(AuthErrors::verificationInvalid);

        if (oldChallenge.isConsumed()) {
            throw AuthErrors.verificationUsed();
        }

        UserAccount account = userAccountRepository.findById(oldChallenge.getUserId())
                .orElseThrow(AuthErrors::verificationInvalid);

        if (account.isDisabled()) {
            throw AuthErrors.accountDisabled();
        }

        // Create a new challenge (invalidate the old one)
        String code = HashUtils.generateCode();
        String codeHash = HashUtils.sha256(code);
        String maskedEmail = HashUtils.maskEmail(account.getEmail());

        Instant challengeExpiresAt = clock.instant().plusSeconds(600);
        VerificationChallenge newChallenge = VerificationChallenge.createCodeChallenge(
                account.getId(), oldChallenge.getPurpose(), maskedEmail,
                codeHash, challengeExpiresAt, 5);
        challengeRepository.save(newChallenge);

        // Send the new code
        emailSender.sendVerificationCode(account.getEmail(), code, challengeExpiresAt);

        Instant resendAvailableAt = clock.instant().plusSeconds(60);
        return new ResendResult(
                newChallenge.getId(),
                null,
                oldChallenge.getPurpose(),
                maskedEmail,
                new String[]{"code"},
                challengeExpiresAt,
                resendAvailableAt);
    }

    public record ResendResult(
            UUID challengeId,
            UUID actionId,
            String purpose,
            String maskedEmail,
            String[] credentialTypes,
            Instant expiresAt,
            Instant resendAvailableAt
    ) {}
}