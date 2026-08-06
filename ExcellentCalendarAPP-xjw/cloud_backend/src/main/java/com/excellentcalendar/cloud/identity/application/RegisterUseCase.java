package com.excellentcalendar.cloud.identity.application;

import com.excellentcalendar.cloud.identity.domain.UserAccount;
import com.excellentcalendar.cloud.identity.domain.UserAccountRepository;
import com.excellentcalendar.cloud.identity.domain.VerificationChallenge;
import com.excellentcalendar.cloud.identity.domain.VerificationChallengeRepository;
import com.excellentcalendar.cloud.identity.infrastructure.UserProfileEntity;
import com.excellentcalendar.cloud.identity.infrastructure.UserProfileJpaRepository;
import com.excellentcalendar.cloud.identity.infrastructure.UserPreferencesEntity;
import com.excellentcalendar.cloud.identity.infrastructure.UserPreferencesJpaRepository;
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
 * Use case: register a new user account.
 */
@Component
public class RegisterUseCase {

    private final UserAccountRepository userAccountRepository;
    private final VerificationChallengeRepository challengeRepository;
    private final UserProfileJpaRepository profileJpaRepository;
    private final UserPreferencesJpaRepository preferencesJpaRepository;
    private final PasswordEncoder passwordEncoder;
    private final EmailSender emailSender;
    private final Clock clock;

    public RegisterUseCase(
            UserAccountRepository userAccountRepository,
            VerificationChallengeRepository challengeRepository,
            UserProfileJpaRepository profileJpaRepository,
            UserPreferencesJpaRepository preferencesJpaRepository,
            PasswordEncoder passwordEncoder,
            EmailSender emailSender,
            Clock clock) {
        this.userAccountRepository = userAccountRepository;
        this.challengeRepository = challengeRepository;
        this.profileJpaRepository = profileJpaRepository;
        this.preferencesJpaRepository = preferencesJpaRepository;
        this.passwordEncoder = passwordEncoder;
        this.emailSender = emailSender;
        this.clock = clock;
    }

    /**
     * Registers a new user with a pending-verification account.
     *
     * @return the registration result with challenge details
     */
    @Transactional
    public RegistrationResult register(
            String email, String username, String displayName,
            String password, String locale, String timezone,
            String agreementVersion, boolean agreementAccepted) {

        // Check for existing email and username
        if (userAccountRepository.existsByEmail(email)) {
            throw AuthErrors.emailAlreadyExists();
        }
        if (userAccountRepository.existsByUsername(username)) {
            throw AuthErrors.usernameAlreadyExists();
        }

        // Create the account
        String passwordHash = passwordEncoder.encode(password);
        UserAccount account = UserAccount.createPending(
                email, passwordHash, agreementVersion, agreementAccepted, clock);
        userAccountRepository.save(account);

        // Create profile
        var profileEntity = new UserProfileEntity();
        profileEntity.setUserId(account.getId());
        profileEntity.setUsername(username);
        profileEntity.setDisplayName(displayName);
        profileEntity.setCreatedAt(clock.instant());
        profileEntity.setUpdatedAt(clock.instant());
        profileJpaRepository.save(profileEntity);

        // Create preferences
        var preferencesEntity = new UserPreferencesEntity();
        preferencesEntity.setUserId(account.getId());
        preferencesEntity.setLocale(locale);
        preferencesEntity.setTimezone(timezone);
        preferencesEntity.setDefaultReminderMethods(new String[]{"popup"});
        preferencesEntity.setSettings("{\"theme\":\"system\"}");
        preferencesEntity.setCreatedAt(clock.instant());
        preferencesEntity.setUpdatedAt(clock.instant());
        preferencesJpaRepository.save(preferencesEntity);

        // Create verification challenge
        String code = HashUtils.generateCode();
        String codeHash = HashUtils.sha256(code);
        String maskedEmail = HashUtils.maskEmail(email);

        Instant challengeExpiresAt = clock.instant().plusSeconds(600);
        VerificationChallenge challenge = VerificationChallenge.createCodeChallenge(
                account.getId(), "registration_verification", maskedEmail,
                codeHash, challengeExpiresAt, 5);
        challengeRepository.save(challenge);

        // Send the verification email
        Instant resendAvailableAt = clock.instant().plusSeconds(60);
        emailSender.sendVerificationCode(email, code, challengeExpiresAt);

        return new RegistrationResult(
                account.getId(),
                challenge.getId(),
                null,
                "registration_verification",
                maskedEmail,
                new String[]{"code"},
                challengeExpiresAt,
                resendAvailableAt);
    }

    public record RegistrationResult(
            UUID accountId,
            UUID challengeId,
            UUID actionId,
            String purpose,
            String maskedEmail,
            String[] credentialTypes,
            Instant expiresAt,
            Instant resendAvailableAt
    ) {}
}