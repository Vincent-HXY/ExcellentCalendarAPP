package com.excellentcalendar.cloud.identity.application;

import com.excellentcalendar.cloud.identity.domain.RefreshTokenGrantRepository;
import com.excellentcalendar.cloud.identity.domain.UserAccount;
import com.excellentcalendar.cloud.identity.domain.UserAccountRepository;
import com.excellentcalendar.cloud.identity.domain.VerificationChallenge;
import com.excellentcalendar.cloud.identity.domain.VerificationChallengeRepository;
import com.excellentcalendar.cloud.platform.password.AuthErrors;
import com.excellentcalendar.cloud.platform.password.HashUtils;
import com.excellentcalendar.cloud.platform.password.PasswordEncoder;
import java.time.Clock;
import java.util.List;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Use case: confirm a password reset and set a new password.
 */
@Component
public class PasswordResetConfirmUseCase {

    private final UserAccountRepository userAccountRepository;
    private final VerificationChallengeRepository challengeRepository;
    private final RefreshTokenGrantRepository grantRepository;
    private final PasswordEncoder passwordEncoder;
    private final Clock clock;

    public PasswordResetConfirmUseCase(
            UserAccountRepository userAccountRepository,
            VerificationChallengeRepository challengeRepository,
            RefreshTokenGrantRepository grantRepository,
            PasswordEncoder passwordEncoder,
            Clock clock) {
        this.userAccountRepository = userAccountRepository;
        this.challengeRepository = challengeRepository;
        this.grantRepository = grantRepository;
        this.passwordEncoder = passwordEncoder;
        this.clock = clock;
    }

    @Transactional
    public void confirmReset(String email, String code, String newPassword) {
        UserAccount account = userAccountRepository.findByEmail(email)
                .orElseThrow(AuthErrors::verificationInvalid);

        if (account.isDisabled()) {
            throw AuthErrors.accountDisabled();
        }

        // Check password policy
        if (newPassword.length() < 8 || newPassword.length() > 128) {
            throw AuthErrors.passwordPolicyViolation();
        }

        // Check old vs new password aren't the same
        if (passwordEncoder.matches(newPassword, account.getPasswordHash())) {
            throw AuthErrors.passwordUnchanged();
        }

        // Verify the code against the latest password_reset challenge
        // We need to find the challenge - since we don't have a findLatestByUserAndPurpose method,
        // we'll use the findByUserId approach and iterate
        // For now, validate the code through the generic challenge lookup
        String codeHash = HashUtils.sha256(code);

        // We need to find a valid challenge for this user
        // Let's use the challenge repository to find by user
        // For simplicity, we verify the code hash matches
        // In a real implementation, we'd have a query to find the latest valid challenge
        var challenges = challengeRepository.findByUserIdAndPurpose(
                account.getId(), "password_reset");

        VerificationChallenge validChallenge = challenges.stream()
                .filter(c -> c.isValid(clock) && codeHash.equals(c.getCodeHash()))
                .findFirst()
                .orElseThrow(AuthErrors::verificationInvalid);

        // Record failed attempt if code doesn't match
        if (!codeHash.equals(validChallenge.getCodeHash())) {
            validChallenge.recordFailedAttempt();
            challengeRepository.save(validChallenge);
            throw AuthErrors.verificationInvalid();
        }

        // Consume the challenge
        validChallenge.consume();
        challengeRepository.save(validChallenge);

        // Update password
        String newPasswordHash = passwordEncoder.encode(newPassword);
        account.updatePassword(newPasswordHash, clock);
        userAccountRepository.save(account);

        // Revoke all sessions
        grantRepository.revokeAllForUser(account.getId(), "password_reset");
    }
}