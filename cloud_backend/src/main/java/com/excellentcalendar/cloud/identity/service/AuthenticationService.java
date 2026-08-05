package com.excellentcalendar.cloud.identity.service;

import com.excellentcalendar.cloud.identity.config.IdentityProperties;
import com.excellentcalendar.cloud.identity.dto.request.SignUpRequest;
import com.excellentcalendar.cloud.identity.dto.response.AuthResponse;
import com.excellentcalendar.cloud.identity.model.EmailChangeRequest;
import com.excellentcalendar.cloud.identity.model.EmailVerificationCode;
import com.excellentcalendar.cloud.identity.model.PasswordResetToken;
import com.excellentcalendar.cloud.identity.model.RefreshToken;
import com.excellentcalendar.cloud.identity.model.UserAccount;
import com.excellentcalendar.cloud.identity.repository.EmailChangeRequestRepository;
import com.excellentcalendar.cloud.identity.repository.EmailVerificationCodeRepository;
import com.excellentcalendar.cloud.identity.repository.PasswordResetTokenRepository;
import com.excellentcalendar.cloud.identity.repository.RefreshTokenRepository;
import com.excellentcalendar.cloud.identity.repository.UserAccountRepository;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional
public class AuthenticationService {

    private static final Logger log = LoggerFactory.getLogger(AuthenticationService.class);
    private static final SecureRandom RANDOM = new SecureRandom();

    private final UserAccountRepository userAccountRepository;
    private final RefreshTokenRepository refreshTokenRepository;
    private final EmailVerificationCodeRepository verificationCodeRepository;
    private final PasswordResetTokenRepository passwordResetTokenRepository;
    private final EmailChangeRequestRepository emailChangeRequestRepository;
    private final JwtTokenProvider jwtTokenProvider;
    private final PasswordEncoder passwordEncoder;
    private final EmailService emailService;
    private final IdentityProperties properties;

    public AuthenticationService(
            UserAccountRepository userAccountRepository,
            RefreshTokenRepository refreshTokenRepository,
            EmailVerificationCodeRepository verificationCodeRepository,
            PasswordResetTokenRepository passwordResetTokenRepository,
            EmailChangeRequestRepository emailChangeRequestRepository,
            JwtTokenProvider jwtTokenProvider,
            PasswordEncoder passwordEncoder,
            EmailService emailService,
            IdentityProperties properties) {
        this.userAccountRepository = userAccountRepository;
        this.refreshTokenRepository = refreshTokenRepository;
        this.verificationCodeRepository = verificationCodeRepository;
        this.passwordResetTokenRepository = passwordResetTokenRepository;
        this.emailChangeRequestRepository = emailChangeRequestRepository;
        this.jwtTokenProvider = jwtTokenProvider;
        this.passwordEncoder = passwordEncoder;
        this.emailService = emailService;
        this.properties = properties;
    }

    // ---------------------------------------------------------------
    // Registration
    // ---------------------------------------------------------------

    public AuthResponse signUp(SignUpRequest request) {
        if (userAccountRepository.existsByEmailIgnoreCase(request.email())) {
            throw new IdentityException.EmailAlreadyExists("Email is already registered");
        }
        if (userAccountRepository.existsByUsernameIgnoreCase(request.username())) {
            throw new IdentityException.UsernameAlreadyTaken("Username is already taken");
        }

        String passwordHash = passwordEncoder.encode(request.password());
        UserAccount account = new UserAccount(
                request.email().toLowerCase().trim(),
                request.username().trim(),
                request.displayName().trim(),
                passwordHash);
        account.setCreatedAt(Instant.now());
        account.setUpdatedAt(Instant.now());

        // Generate a random initial display name if not provided
        if (account.getDisplayName() == null || account.getDisplayName().isBlank()) {
            account.setDisplayName("User" + RANDOM.nextInt(10000, 99999));
        }

        account = userAccountRepository.save(account);

        // Send verification code
        sendVerificationCode(account);

        // Issue tokens
        String accessToken = jwtTokenProvider.createAccessToken(account.getId());
        String refreshToken = jwtTokenProvider.createRefreshToken(account.getId());
        saveRefreshToken(account, refreshToken);

        log.info("User registered: id={}, email={}", account.getId(), account.getEmail());

        return buildAuthResponse(account, accessToken, refreshToken);
    }

    // ---------------------------------------------------------------
    // Login
    // ---------------------------------------------------------------

    public AuthResponse login(String email, String password) {
        UserAccount account = userAccountRepository.findByEmailIgnoreCase(email.trim())
                .orElseThrow(() -> new IdentityException.InvalidCredentials("Invalid email or password"));

        if (!account.isEnabled()) {
            throw new IdentityException.AccountDisabled("Account is disabled");
        }

        if (!passwordEncoder.matches(password, account.getPasswordHash())) {
            throw new IdentityException.InvalidCredentials("Invalid email or password");
        }

        // Issue tokens
        String accessToken = jwtTokenProvider.createAccessToken(account.getId());
        String refreshToken = jwtTokenProvider.createRefreshToken(account.getId());
        saveRefreshToken(account, refreshToken);

        log.info("User logged in: id={}", account.getId());

        return buildAuthResponse(account, accessToken, refreshToken);
    }

    // ---------------------------------------------------------------
    // Token refresh
    // ---------------------------------------------------------------

    public AuthResponse refreshToken(String refreshTokenValue) {
        if (!jwtTokenProvider.validateToken(refreshTokenValue)) {
            throw new IdentityException.InvalidToken("Invalid or expired refresh token");
        }

        UUID userId = jwtTokenProvider.getUserIdFromToken(refreshTokenValue);
        String tokenHash = hashToken(refreshTokenValue);

        RefreshToken storedToken = refreshTokenRepository.findByTokenHash(tokenHash)
                .orElseThrow(() -> new IdentityException.InvalidToken("Refresh token not found"));

        if (!storedToken.isValid()) {
            throw new IdentityException.InvalidToken("Refresh token is revoked or expired");
        }

        // Rotate: revoke old token
        storedToken.setRevokedAt(Instant.now());
        refreshTokenRepository.save(storedToken);

        // Issue new tokens
        UserAccount account = storedToken.getUserAccount();
        String newAccessToken = jwtTokenProvider.createAccessToken(account.getId());
        String newRefreshToken = jwtTokenProvider.createRefreshToken(account.getId());
        saveRefreshToken(account, newRefreshToken);

        log.info("Token refreshed for user: id={}", account.getId());

        return buildAuthResponse(account, newAccessToken, newRefreshToken);
    }

    // ---------------------------------------------------------------
    // Email verification
    // ---------------------------------------------------------------

    public void sendVerificationCode(UserAccount account) {
        // Rate limit check
        Instant windowStart = Instant.now().minus(properties.getVerificationCodeWindow());
        long count = verificationCodeRepository
                .countByUserAccountIdAndCreatedAtAfter(account.getId(), windowStart);
        if (count >= properties.getVerificationCodeMaxPerWindow()) {
            throw new IdentityException.RateLimitExceeded("Too many verification requests. Please try again later.");
        }

        String code = generateCode();
        Instant expiresAt = Instant.now().plus(properties.getVerificationCodeExpiration());

        EmailVerificationCode verificationCode = new EmailVerificationCode(
                account, account.getEmail(), code, expiresAt, Instant.now());
        verificationCodeRepository.save(verificationCode);

        emailService.sendVerificationCode(account.getEmail(), code);
    }

    public AuthResponse verifyEmail(UUID userId, String code) {
        UserAccount account = userAccountRepository.findById(userId)
                .orElseThrow(() -> new IdentityException.UserNotFound("User not found"));

        if (account.isEmailVerified()) {
            throw new IdentityException.EmailAlreadyVerified("Email is already verified");
        }

        EmailVerificationCode verificationCode = verificationCodeRepository
                .findTopByUserAccountIdAndCodeAndVerifiedAtIsNullOrderByCreatedAtDesc(userId, code)
                .orElseThrow(() -> new IdentityException.InvalidVerificationCode("Invalid verification code"));

        if (!verificationCode.isValid()) {
            throw new IdentityException.InvalidVerificationCode("Verification code has expired");
        }

        verificationCode.setVerifiedAt(Instant.now());
        verificationCodeRepository.save(verificationCode);

        account.setEmailVerifiedAt(Instant.now());
        account.setUpdatedAt(Instant.now());
        userAccountRepository.save(account);

        // Issue tokens
        String accessToken = jwtTokenProvider.createAccessToken(account.getId());
        String refreshToken = jwtTokenProvider.createRefreshToken(account.getId());
        saveRefreshToken(account, refreshToken);

        log.info("Email verified for user: id={}", account.getId());

        return buildAuthResponse(account, accessToken, refreshToken);
    }

    public void resendVerificationCode(UUID userId) {
        UserAccount account = userAccountRepository.findById(userId)
                .orElseThrow(() -> new IdentityException.UserNotFound("User not found"));

        if (account.isEmailVerified()) {
            throw new IdentityException.EmailAlreadyVerified("Email is already verified");
        }

        sendVerificationCode(account);
    }

    // ---------------------------------------------------------------
    // Password reset (forgot password)
    // ---------------------------------------------------------------

    public void forgotPassword(String email) {
        // Always return the same message regardless of whether the email exists
        // to avoid leaking account existence information.
        userAccountRepository.findByEmailIgnoreCase(email.trim()).ifPresent(account -> {
            String code = generateCode();
            String codeHash = hashToken(code);
            Instant expiresAt = Instant.now().plus(properties.getPasswordResetExpiration());

            PasswordResetToken resetToken = new PasswordResetToken(
                    account, codeHash, expiresAt, Instant.now());
            passwordResetTokenRepository.save(resetToken);

            emailService.sendPasswordResetToken(account.getEmail(), code);
            log.info("Password reset code sent to user: id={}", account.getId());
        });

        log.info("Password reset requested for email: {}", email);
    }

    public void resetPassword(String code, String newPassword) {
        String codeHash = hashToken(code);

        PasswordResetToken resetToken = passwordResetTokenRepository
                .findTopByTokenHashAndUsedAtIsNullOrderByCreatedAtDesc(codeHash)
                .orElseThrow(() -> new IdentityException.InvalidToken("Invalid or expired password reset code"));

        if (!resetToken.isValid()) {
            throw new IdentityException.InvalidToken("Password reset code has expired");
        }

        UserAccount account = resetToken.getUserAccount();

        // Check new password is not the same as old
        if (passwordEncoder.matches(newPassword, account.getPasswordHash())) {
            throw new IdentityException.InvalidPassword("New password must be different from the current password");
        }

        // Update password
        account.setPasswordHash(passwordEncoder.encode(newPassword));
        account.setUpdatedAt(Instant.now());
        userAccountRepository.save(account);

        // Mark token as used
        resetToken.setUsedAt(Instant.now());
        passwordResetTokenRepository.save(resetToken);

        // Revoke all existing refresh tokens for this account
        revokeAllRefreshTokens(account);

        log.info("Password reset for user: id={}", account.getId());
    }

    // ---------------------------------------------------------------
    // Change password (authenticated)
    // ---------------------------------------------------------------

    public AuthResponse changePassword(UUID userId, String currentPassword, String newPassword) {
        UserAccount account = userAccountRepository.findById(userId)
                .orElseThrow(() -> new IdentityException.UserNotFound("User not found"));

        if (!passwordEncoder.matches(currentPassword, account.getPasswordHash())) {
            throw new IdentityException.InvalidCredentials("Current password is incorrect");
        }

        if (passwordEncoder.matches(newPassword, account.getPasswordHash())) {
            throw new IdentityException.InvalidPassword("New password must be different from the current password");
        }

        // Update password
        account.setPasswordHash(passwordEncoder.encode(newPassword));
        account.setUpdatedAt(Instant.now());
        userAccountRepository.save(account);

        // Revoke all other sessions (keep current device)
        revokeAllRefreshTokens(account);

        // Issue new tokens for current device
        String accessToken = jwtTokenProvider.createAccessToken(account.getId());
        String refreshToken = jwtTokenProvider.createRefreshToken(account.getId());
        saveRefreshToken(account, refreshToken);

        log.info("Password changed for user: id={}", account.getId());

        return buildAuthResponse(account, accessToken, refreshToken);
    }

    // ---------------------------------------------------------------
    // Change email
    // ---------------------------------------------------------------

    public void requestEmailChange(UUID userId, String newEmail, String currentPassword) {
        UserAccount account = userAccountRepository.findById(userId)
                .orElseThrow(() -> new IdentityException.UserNotFound("User not found"));

        if (!passwordEncoder.matches(currentPassword, account.getPasswordHash())) {
            throw new IdentityException.InvalidCredentials("Current password is incorrect");
        }

        if (userAccountRepository.existsByEmailIgnoreCase(newEmail)) {
            throw new IdentityException.EmailAlreadyExists("Email is already in use");
        }

        // Revoke any previous pending email change requests for this user
        emailChangeRequestRepository.deleteByUserAccountId(userId);

        String code = generateCode();
        Instant expiresAt = Instant.now().plus(properties.getEmailChangeExpiration());

        EmailChangeRequest changeRequest = new EmailChangeRequest(
                account, newEmail, code, expiresAt, Instant.now());
        emailChangeRequestRepository.save(changeRequest);

        emailService.sendVerificationCode(newEmail, code);

        log.info("Email change requested for user: id={}, newEmail={}", userId, newEmail);
    }

    // ---------------------------------------------------------------
    // Logout
    // ---------------------------------------------------------------

    public void logout(String refreshTokenValue) {
        String tokenHash = hashToken(refreshTokenValue);
        refreshTokenRepository.findByTokenHash(tokenHash).ifPresent(token -> {
            token.setRevokedAt(Instant.now());
            refreshTokenRepository.save(token);
        });
    }

    public void logoutAllDevices(UUID userId) {
        userAccountRepository.findById(userId).ifPresent(account -> {
            revokeAllRefreshTokens(account);
        });
    }

    // ---------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------

    private void saveRefreshToken(UserAccount account, String refreshToken) {
        String tokenHash = hashToken(refreshToken);
        Instant expiresAt = jwtTokenProvider.getExpirationFromToken(refreshToken);
        RefreshToken token = new RefreshToken(account, tokenHash, expiresAt, Instant.now());
        refreshTokenRepository.save(token);
    }

    private void revokeAllRefreshTokens(UserAccount account) {
        refreshTokenRepository.findByUserAccountIdAndRevokedAtIsNull(account.getId())
                .forEach(token -> {
                    token.setRevokedAt(Instant.now());
                    refreshTokenRepository.save(token);
                });
    }

    private AuthResponse buildAuthResponse(UserAccount account, String accessToken, String refreshToken) {
        long expiresIn = properties.getAccessTokenExpiration().toSeconds();
        return new AuthResponse(
                account.getId(),
                account.getEmail(),
                account.getUsername(),
                account.getDisplayName(),
                account.getAvatarUrl(),
                account.getLanguage(),
                account.getTimezone(),
                account.isEmailVerified(),
                accessToken,
                refreshToken,
                expiresIn);
    }

    private String generateCode() {
        int code = RANDOM.nextInt(100000, 999999);
        return String.valueOf(code);
    }

    private String hashToken(String token) {
        try {
            java.security.MessageDigest digest = java.security.MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest(token.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            return java.util.HexFormat.of().formatHex(hash);
        } catch (java.security.NoSuchAlgorithmException e) {
            throw new RuntimeException("SHA-256 not available", e);
        }
    }
}