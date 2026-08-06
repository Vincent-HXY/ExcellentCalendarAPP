package com.excellentcalendar.cloud.identity.application;

import com.excellentcalendar.cloud.identity.domain.UserAccount;
import com.excellentcalendar.cloud.identity.domain.UserAccountRepository;
import com.excellentcalendar.cloud.identity.domain.VerificationChallenge;
import com.excellentcalendar.cloud.identity.domain.VerificationChallengeRepository;
import com.excellentcalendar.cloud.platform.mail.EmailSender;
import com.excellentcalendar.cloud.platform.password.HashUtils;
import java.time.Clock;
import java.time.Instant;
import java.util.Optional;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Use case: request a password reset email.
 * Returns the same result for both registered and unregistered emails.
 */
@Component
public class PasswordResetRequestUseCase {

    private final UserAccountRepository userAccountRepository;
    private final VerificationChallengeRepository challengeRepository;
    private final EmailSender emailSender;
    private final Clock clock;

    public PasswordResetRequestUseCase(
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
    public PasswordResetRequestResult requestReset(String email) {
        Optional<UserAccount> accountOpt = userAccountRepository.findByEmail(email);

        Instant resendAvailableAt = clock.instant().plusSeconds(60);

        // Return same result for registered and unregistered emails
        if (accountOpt.isEmpty()) {
            return new PasswordResetRequestResult(true, resendAvailableAt);
        }

        UserAccount account = accountOpt.get();

        // Create a verification challenge
        String code = HashUtils.generateCode();
        String codeHash = HashUtils.sha256(code);
        String maskedEmail = HashUtils.maskEmail(account.getEmail());

        Instant challengeExpiresAt = clock.instant().plusSeconds(900);
        VerificationChallenge challenge = VerificationChallenge.createCodeChallenge(
                account.getId(), "password_reset", maskedEmail,
                codeHash, challengeExpiresAt, 5);
        challengeRepository.save(challenge);

        // Send the email
        emailSender.sendPasswordResetCode(account.getEmail(), code, challengeExpiresAt);

        return new PasswordResetRequestResult(true, resendAvailableAt);
    }

    public record PasswordResetRequestResult(boolean accepted, Instant resendAvailableAt) {}
}