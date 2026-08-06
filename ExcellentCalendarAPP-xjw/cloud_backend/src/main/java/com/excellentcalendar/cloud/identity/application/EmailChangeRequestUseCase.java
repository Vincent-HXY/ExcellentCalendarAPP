package com.excellentcalendar.cloud.identity.application;

import com.excellentcalendar.cloud.identity.domain.EmailChangeRequest;
import com.excellentcalendar.cloud.identity.domain.EmailChangeRequestRepository;
import com.excellentcalendar.cloud.identity.domain.UserAccount;
import com.excellentcalendar.cloud.identity.domain.UserAccountRepository;
import com.excellentcalendar.cloud.identity.domain.VerificationChallenge;
import com.excellentcalendar.cloud.identity.domain.VerificationChallengeRepository;
import com.excellentcalendar.cloud.platform.mail.EmailSender;
import com.excellentcalendar.cloud.platform.password.AuthErrors;
import com.excellentcalendar.cloud.platform.password.HashUtils;
import com.excellentcalendar.cloud.platform.password.PasswordEncoder;
import java.time.Clock;
import java.time.Instant;
import java.util.UUID;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Use case: request an email change by verifying the current password.
 */
@Component
public class EmailChangeRequestUseCase {

    private final UserAccountRepository userAccountRepository;
    private final EmailChangeRequestRepository emailChangeRequestRepository;
    private final VerificationChallengeRepository challengeRepository;
    private final PasswordEncoder passwordEncoder;
    private final EmailSender emailSender;
    private final Clock clock;

    public EmailChangeRequestUseCase(
            UserAccountRepository userAccountRepository,
            EmailChangeRequestRepository emailChangeRequestRepository,
            VerificationChallengeRepository challengeRepository,
            PasswordEncoder passwordEncoder,
            EmailSender emailSender,
            Clock clock) {
        this.userAccountRepository = userAccountRepository;
        this.emailChangeRequestRepository = emailChangeRequestRepository;
        this.challengeRepository = challengeRepository;
        this.passwordEncoder = passwordEncoder;
        this.emailSender = emailSender;
        this.clock = clock;
    }

    @Transactional
    public EmailChangeRequestResult requestEmailChange(
            UUID userId, String newEmail, String currentPassword) {

        UserAccount account = userAccountRepository.findById(userId)
                .orElseThrow(AuthErrors::sessionExpired);

        if (account.isDisabled()) {
            throw AuthErrors.accountDisabled();
        }

        // Verify current password
        if (!passwordEncoder.matches(currentPassword, account.getPasswordHash())) {
            throw AuthErrors.currentPasswordInvalid();
        }

        // Check new email is not already in use
        if (userAccountRepository.existsByEmail(newEmail)) {
            throw AuthErrors.emailAlreadyExists();
        }

        // Create verification challenge for the new email
        String code = HashUtils.generateCode();
        String codeHash = HashUtils.sha256(code);
        String maskedNewEmail = HashUtils.maskEmail(newEmail);

        Instant challengeExpiresAt = clock.instant().plusSeconds(600);
        VerificationChallenge challenge = VerificationChallenge.createCodeChallenge(
                userId, "email_change", maskedNewEmail,
                codeHash, challengeExpiresAt, 5);
        challengeRepository.save(challenge);

        // Create the email change request
        Instant requestExpiresAt = clock.instant().plusSeconds(600);
        EmailChangeRequest emailChangeRequest = EmailChangeRequest.createPending(
                userId, account.getEmail(), newEmail,
                challenge.getId(), requestExpiresAt, clock);
        emailChangeRequestRepository.save(emailChangeRequest);

        // Send verification to the new email
        emailSender.sendVerificationCode(newEmail, code, challengeExpiresAt);

        Instant resendAvailableAt = clock.instant().plusSeconds(60);
        return new EmailChangeRequestResult(
                challenge.getId(),
                emailChangeRequest.getId(),
                "email_change",
                maskedNewEmail,
                new String[]{"code"},
                challengeExpiresAt,
                resendAvailableAt);
    }

    public record EmailChangeRequestResult(
            UUID challengeId,
            UUID actionId,
            String purpose,
            String maskedEmail,
            String[] credentialTypes,
            Instant expiresAt,
            Instant resendAvailableAt
    ) {}
}