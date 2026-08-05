package com.excellentcalendar.cloud.identity.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.excellentcalendar.cloud.identity.config.IdentityProperties;
import com.excellentcalendar.cloud.identity.dto.request.SignUpRequest;
import com.excellentcalendar.cloud.identity.dto.response.AuthResponse;
import com.excellentcalendar.cloud.identity.model.EmailVerificationCode;
import com.excellentcalendar.cloud.identity.model.PasswordResetToken;
import com.excellentcalendar.cloud.identity.model.RefreshToken;
import com.excellentcalendar.cloud.identity.model.UserAccount;
import com.excellentcalendar.cloud.identity.repository.EmailChangeRequestRepository;
import com.excellentcalendar.cloud.identity.repository.EmailVerificationCodeRepository;
import com.excellentcalendar.cloud.identity.repository.PasswordResetTokenRepository;
import com.excellentcalendar.cloud.identity.repository.RefreshTokenRepository;
import com.excellentcalendar.cloud.identity.repository.UserAccountRepository;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Captor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.password.PasswordEncoder;

@ExtendWith(MockitoExtension.class)
class AuthenticationServiceTest {

    @Mock
    private UserAccountRepository userAccountRepository;
    @Mock
    private RefreshTokenRepository refreshTokenRepository;
    @Mock
    private EmailVerificationCodeRepository verificationCodeRepository;
    @Mock
    private PasswordResetTokenRepository passwordResetTokenRepository;
    @Mock
    private EmailChangeRequestRepository emailChangeRequestRepository;
    @Mock
    private JwtTokenProvider jwtTokenProvider;
    @Mock
    private PasswordEncoder passwordEncoder;
    @Mock
    private EmailService emailService;
    @Mock
    private IdentityProperties properties;

    @Captor
    private ArgumentCaptor<UserAccount> userAccountCaptor;
    @Captor
    private ArgumentCaptor<RefreshToken> refreshTokenCaptor;
    @Captor
    private ArgumentCaptor<PasswordResetToken> passwordResetTokenCaptor;

    private AuthenticationService service;
    private UUID userId;
    private UserAccount account;
    private String accessToken;
    private String refreshTokenValue;

    @BeforeEach
    void setUp() {
        service = new AuthenticationService(
                userAccountRepository, refreshTokenRepository,
                verificationCodeRepository, passwordResetTokenRepository,
                emailChangeRequestRepository,
                jwtTokenProvider, passwordEncoder, emailService, properties);

        userId = UUID.randomUUID();
        accessToken = "access-token-value";
        refreshTokenValue = "refresh-token-value";

        account = new UserAccount("test@example.com", "testuser", "Test User", "hashed-password");
        account.setId(userId);
        account.setCreatedAt(Instant.now());
        account.setUpdatedAt(Instant.now());
        account.setLanguage("en");
        account.setTimezone("UTC");

        lenient().when(properties.getAccessTokenExpiration()).thenReturn(Duration.ofMinutes(15));
        lenient().when(userAccountRepository.save(any(UserAccount.class))).thenAnswer(invocation -> invocation.getArgument(0));
        lenient().when(refreshTokenRepository.save(any(RefreshToken.class))).thenAnswer(invocation -> invocation.getArgument(0));
    }

    // ---------------------------------------------------------------
    // Registration
    // ---------------------------------------------------------------

    @Nested
    @DisplayName("signUp()")
    class SignUp {

        @Test
        @DisplayName("should return AuthResponse when registration succeeds")
        void shouldReturnAuthResponse_whenRegistrationSucceeds() {
            SignUpRequest request = new SignUpRequest("new@example.com", "newuser", "New User", "password123");
            when(userAccountRepository.existsByEmailIgnoreCase("new@example.com")).thenReturn(false);
            when(userAccountRepository.existsByUsernameIgnoreCase("newuser")).thenReturn(false);
            when(passwordEncoder.encode("password123")).thenReturn("encoded-password");
            when(userAccountRepository.save(any(UserAccount.class))).thenAnswer(invocation -> {
                UserAccount saved = invocation.getArgument(0);
                saved.setId(userId);
                return saved;
            });
            when(jwtTokenProvider.createAccessToken(userId)).thenReturn(accessToken);
            when(jwtTokenProvider.createRefreshToken(userId)).thenReturn(refreshTokenValue);
            when(properties.getAccessTokenExpiration()).thenReturn(Duration.ofMinutes(15));
            when(properties.getVerificationCodeExpiration()).thenReturn(Duration.ofMinutes(15));
            when(properties.getVerificationCodeMaxPerWindow()).thenReturn(3);
            when(properties.getVerificationCodeWindow()).thenReturn(Duration.ofMinutes(10));
            when(verificationCodeRepository.countByUserAccountIdAndCreatedAtAfter(any(UUID.class), any(Instant.class)))
                    .thenReturn(0L);

            AuthResponse response = service.signUp(request);

            assertThat(response).isNotNull();
            assertThat(response.accessToken()).isEqualTo(accessToken);
            assertThat(response.refreshToken()).isEqualTo(refreshTokenValue);
            assertThat(response.email()).isEqualTo("new@example.com");
            verify(userAccountRepository).save(any(UserAccount.class));
            verify(jwtTokenProvider).createAccessToken(userId);
            verify(jwtTokenProvider).createRefreshToken(userId);
        }

        @Test
        @DisplayName("should throw EmailAlreadyExists when email is taken")
        void shouldThrowEmailAlreadyExists_whenEmailIsTaken() {
            SignUpRequest request = new SignUpRequest("existing@example.com", "newuser", "New User", "password123");
            when(userAccountRepository.existsByEmailIgnoreCase("existing@example.com")).thenReturn(true);

            assertThatThrownBy(() -> service.signUp(request))
                    .isInstanceOf(IdentityException.EmailAlreadyExists.class);
        }

        @Test
        @DisplayName("should throw UsernameAlreadyTaken when username is taken")
        void shouldThrowUsernameAlreadyTaken_whenUsernameIsTaken() {
            SignUpRequest request = new SignUpRequest("new@example.com", "takenuser", "New User", "password123");
            when(userAccountRepository.existsByEmailIgnoreCase("new@example.com")).thenReturn(false);
            when(userAccountRepository.existsByUsernameIgnoreCase("takenuser")).thenReturn(true);

            assertThatThrownBy(() -> service.signUp(request))
                    .isInstanceOf(IdentityException.UsernameAlreadyTaken.class);
        }
    }

    // ---------------------------------------------------------------
    // Login
    // ---------------------------------------------------------------

    @Nested
    @DisplayName("login()")
    class Login {

        @Test
        @DisplayName("should return AuthResponse when credentials are valid")
        void shouldReturnAuthResponse_whenCredentialsAreValid() {
            when(userAccountRepository.findByEmailIgnoreCase("test@example.com")).thenReturn(Optional.of(account));
            when(passwordEncoder.matches("correct-password", account.getPasswordHash())).thenReturn(true);
            when(jwtTokenProvider.createAccessToken(userId)).thenReturn(accessToken);
            when(jwtTokenProvider.createRefreshToken(userId)).thenReturn(refreshTokenValue);

            AuthResponse response = service.login("test@example.com", "correct-password");

            assertThat(response).isNotNull();
            assertThat(response.accessToken()).isEqualTo(accessToken);
            assertThat(response.email()).isEqualTo("test@example.com");
        }

        @Test
        @DisplayName("should throw InvalidCredentials when password is wrong")
        void shouldThrowInvalidCredentials_whenPasswordIsWrong() {
            when(userAccountRepository.findByEmailIgnoreCase("test@example.com")).thenReturn(Optional.of(account));
            when(passwordEncoder.matches("wrong-password", account.getPasswordHash())).thenReturn(false);

            assertThatThrownBy(() -> service.login("test@example.com", "wrong-password"))
                    .isInstanceOf(IdentityException.InvalidCredentials.class);
        }

        @Test
        @DisplayName("should throw AccountDisabled when account is disabled")
        void shouldThrowAccountDisabled_whenAccountIsDisabled() {
            account.setEnabled(false);
            when(userAccountRepository.findByEmailIgnoreCase("test@example.com")).thenReturn(Optional.of(account));

            assertThatThrownBy(() -> service.login("test@example.com", "password"))
                    .isInstanceOf(IdentityException.AccountDisabled.class);
        }
    }

    // ---------------------------------------------------------------
    // Token refresh
    // ---------------------------------------------------------------

    @Nested
    @DisplayName("refreshToken()")
    class RefreshTokenTest {

        @Test
        @DisplayName("should return new AuthResponse when token is valid")
        void shouldReturnNewAuthResponse_whenTokenIsValid() {
            String newAccessToken = "new-access-token";
            String newRefreshToken = "new-refresh-token";
            RefreshToken storedToken = new RefreshToken(account, "token-hash", Instant.now().plus(Duration.ofDays(30)),
                    Instant.now());

            when(jwtTokenProvider.validateToken(refreshTokenValue)).thenReturn(true);
            when(jwtTokenProvider.getUserIdFromToken(refreshTokenValue)).thenReturn(userId);
            when(refreshTokenRepository.findByTokenHash(anyString())).thenReturn(Optional.of(storedToken));
            when(jwtTokenProvider.createAccessToken(userId)).thenReturn(newAccessToken);
            when(jwtTokenProvider.createRefreshToken(userId)).thenReturn(newRefreshToken);
            when(jwtTokenProvider.getExpirationFromToken(newRefreshToken)).thenReturn(Instant.now().plus(Duration.ofDays(30)));

            AuthResponse response = service.refreshToken(refreshTokenValue);

            assertThat(response).isNotNull();
            assertThat(response.accessToken()).isEqualTo(newAccessToken);
            assertThat(response.refreshToken()).isEqualTo(newRefreshToken);
            assertThat(storedToken.isRevoked()).isTrue();
        }

        @Test
        @DisplayName("should throw InvalidToken when token is invalid")
        void shouldThrowInvalidToken_whenTokenIsInvalid() {
            when(jwtTokenProvider.validateToken("invalid-token")).thenReturn(false);

            assertThatThrownBy(() -> service.refreshToken("invalid-token"))
                    .isInstanceOf(IdentityException.InvalidToken.class);
        }

        @Test
        @DisplayName("should throw InvalidToken when token is revoked")
        void shouldThrowInvalidToken_whenTokenIsRevoked() {
            RefreshToken revokedToken = new RefreshToken(account, "token-hash", Instant.now().plus(Duration.ofDays(30)),
                    Instant.now());
            revokedToken.setRevokedAt(Instant.now());

            when(jwtTokenProvider.validateToken(refreshTokenValue)).thenReturn(true);
            when(jwtTokenProvider.getUserIdFromToken(refreshTokenValue)).thenReturn(userId);
            when(refreshTokenRepository.findByTokenHash(anyString())).thenReturn(Optional.of(revokedToken));

            assertThatThrownBy(() -> service.refreshToken(refreshTokenValue))
                    .isInstanceOf(IdentityException.InvalidToken.class);
        }
    }

    // ---------------------------------------------------------------
    // Email verification
    // ---------------------------------------------------------------

    @Nested
    @DisplayName("verifyEmail()")
    class VerifyEmail {

        @Test
        @DisplayName("should verify email when code is valid")
        void shouldVerifyEmail_whenCodeIsValid() {
            String code = "123456";
            EmailVerificationCode verificationCode = new EmailVerificationCode(
                    account, account.getEmail(), code, Instant.now().plus(Duration.ofMinutes(15)), Instant.now());

            when(userAccountRepository.findById(userId)).thenReturn(Optional.of(account));
            when(verificationCodeRepository.findTopByUserAccountIdAndCodeAndVerifiedAtIsNullOrderByCreatedAtDesc(
                    userId, code)).thenReturn(Optional.of(verificationCode));
            when(jwtTokenProvider.createAccessToken(userId)).thenReturn(accessToken);
            when(jwtTokenProvider.createRefreshToken(userId)).thenReturn(refreshTokenValue);

            AuthResponse response = service.verifyEmail(userId, code);

            assertThat(response).isNotNull();
            assertThat(account.isEmailVerified()).isTrue();
            assertThat(verificationCode.isVerified()).isTrue();
        }

        @Test
        @DisplayName("should throw EmailAlreadyVerified when email is already verified")
        void shouldThrowEmailAlreadyVerified_whenEmailAlreadyVerified() {
            account.setEmailVerifiedAt(Instant.now());
            when(userAccountRepository.findById(userId)).thenReturn(Optional.of(account));

            assertThatThrownBy(() -> service.verifyEmail(userId, "123456"))
                    .isInstanceOf(IdentityException.EmailAlreadyVerified.class);
        }

        @Test
        @DisplayName("should throw InvalidVerificationCode when code is invalid")
        void shouldThrowInvalidVerificationCode_whenCodeIsInvalid() {
            when(userAccountRepository.findById(userId)).thenReturn(Optional.of(account));
            when(verificationCodeRepository.findTopByUserAccountIdAndCodeAndVerifiedAtIsNullOrderByCreatedAtDesc(
                    userId, "wrong-code")).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.verifyEmail(userId, "wrong-code"))
                    .isInstanceOf(IdentityException.InvalidVerificationCode.class);
        }
    }

    // ---------------------------------------------------------------
    // Password reset
    // ---------------------------------------------------------------

    @Nested
    @DisplayName("forgotPassword()")
    class ForgotPassword {

        @Test
        @DisplayName("should send reset email when email exists")
        void shouldSendResetEmail_whenEmailExists() {
            when(userAccountRepository.findByEmailIgnoreCase("test@example.com")).thenReturn(Optional.of(account));
            when(properties.getPasswordResetExpiration()).thenReturn(Duration.ofMinutes(30));

            service.forgotPassword("test@example.com");

            verify(passwordResetTokenRepository).save(any(PasswordResetToken.class));
            verify(emailService).sendPasswordResetToken(eq("test@example.com"), anyString());
        }

        @Test
        @DisplayName("should not send email when email does not exist")
        void shouldNotSendEmail_whenEmailDoesNotExist() {
            when(userAccountRepository.findByEmailIgnoreCase("nonexistent@example.com")).thenReturn(Optional.empty());

            service.forgotPassword("nonexistent@example.com");

            verify(passwordResetTokenRepository, never()).save(any());
            verify(emailService, never()).sendPasswordResetToken(anyString(), anyString());
        }
    }

    @Nested
    @DisplayName("resetPassword()")
    class ResetPassword {

        @Test
        @DisplayName("should reset password when token is valid")
        void shouldResetPassword_whenTokenIsValid() {
            String code = "123456";
            String newPassword = "new-password-123";
            PasswordResetToken resetToken = new PasswordResetToken(
                    account, "hash", Instant.now().plus(Duration.ofMinutes(30)), Instant.now());

            when(passwordResetTokenRepository.findTopByTokenHashAndUsedAtIsNullOrderByCreatedAtDesc(anyString()))
                    .thenReturn(Optional.of(resetToken));
            when(passwordEncoder.matches(newPassword, account.getPasswordHash())).thenReturn(false);
            when(passwordEncoder.encode(newPassword)).thenReturn("new-encoded-password");
            when(refreshTokenRepository.findByUserAccountIdAndRevokedAtIsNull(userId)).thenReturn(List.of());

            service.resetPassword(code, newPassword);

            assertThat(resetToken.isUsed()).isTrue();
            verify(userAccountRepository).save(account);
        }

        @Test
        @DisplayName("should throw InvalidPassword when new password is same as old")
        void shouldThrowInvalidPassword_whenNewPasswordSameAsOld() {
            String code = "123456";
            String newPassword = "same-as-old-password";
            PasswordResetToken resetToken = new PasswordResetToken(
                    account, "hash", Instant.now().plus(Duration.ofMinutes(30)), Instant.now());

            when(passwordResetTokenRepository.findTopByTokenHashAndUsedAtIsNullOrderByCreatedAtDesc(anyString()))
                    .thenReturn(Optional.of(resetToken));
            when(passwordEncoder.matches(newPassword, account.getPasswordHash())).thenReturn(true);

            assertThatThrownBy(() -> service.resetPassword(code, newPassword))
                    .isInstanceOf(IdentityException.InvalidPassword.class);
        }

        @Test
        @DisplayName("should throw InvalidToken when token is invalid")
        void shouldThrowInvalidToken_whenTokenIsInvalid() {
            when(passwordResetTokenRepository.findTopByTokenHashAndUsedAtIsNullOrderByCreatedAtDesc(anyString()))
                    .thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.resetPassword("invalid-code", "new-password-123"))
                    .isInstanceOf(IdentityException.InvalidToken.class);
        }
    }

    // ---------------------------------------------------------------
    // Change password
    // ---------------------------------------------------------------

    @Nested
    @DisplayName("changePassword()")
    class ChangePassword {

        @Test
        @DisplayName("should change password and issue new tokens when current password is correct")
        void shouldChangePassword_whenCurrentPasswordIsCorrect() {
            String currentPassword = "current-password";
            String newPassword = "new-password-123";

            when(userAccountRepository.findById(userId)).thenReturn(Optional.of(account));
            when(passwordEncoder.matches(currentPassword, account.getPasswordHash())).thenReturn(true);
            when(passwordEncoder.matches(newPassword, account.getPasswordHash())).thenReturn(false);
            when(passwordEncoder.encode(newPassword)).thenReturn("new-encoded-password");
            when(refreshTokenRepository.findByUserAccountIdAndRevokedAtIsNull(userId)).thenReturn(List.of());
            when(jwtTokenProvider.createAccessToken(userId)).thenReturn(accessToken);
            when(jwtTokenProvider.createRefreshToken(userId)).thenReturn(refreshTokenValue);

            AuthResponse response = service.changePassword(userId, currentPassword, newPassword);

            assertThat(response).isNotNull();
            assertThat(response.accessToken()).isEqualTo(accessToken);
            verify(userAccountRepository).save(account);
        }

        @Test
        @DisplayName("should throw InvalidCredentials when current password is wrong")
        void shouldThrowInvalidCredentials_whenCurrentPasswordIsWrong() {
            when(userAccountRepository.findById(userId)).thenReturn(Optional.of(account));
            when(passwordEncoder.matches("wrong-password", account.getPasswordHash())).thenReturn(false);

            assertThatThrownBy(() -> service.changePassword(userId, "wrong-password", "new-password-123"))
                    .isInstanceOf(IdentityException.InvalidCredentials.class);
        }
    }

    // ---------------------------------------------------------------
    // Logout
    // ---------------------------------------------------------------

    @Nested
    @DisplayName("logout() / logoutAllDevices()")
    class Logout {

        @Test
        @DisplayName("should revoke the refresh token on logout")
        void shouldRevokeToken_onLogout() {
            RefreshToken storedToken = new RefreshToken(
                    account, "token-hash", Instant.now().plus(Duration.ofDays(30)), Instant.now());
            when(refreshTokenRepository.findByTokenHash(anyString())).thenReturn(Optional.of(storedToken));

            service.logout(refreshTokenValue);

            assertThat(storedToken.isRevoked()).isTrue();
        }

        @Test
        @DisplayName("should revoke all tokens on logoutAllDevices")
        void shouldRevokeAllTokens_onLogoutAllDevices() {
            RefreshToken token1 = new RefreshToken(account, "hash1", Instant.now().plus(Duration.ofDays(30)),
                    Instant.now());
            RefreshToken token2 = new RefreshToken(account, "hash2", Instant.now().plus(Duration.ofDays(30)),
                    Instant.now());
            when(userAccountRepository.findById(userId)).thenReturn(Optional.of(account));
            when(refreshTokenRepository.findByUserAccountIdAndRevokedAtIsNull(userId))
                    .thenReturn(List.of(token1, token2));

            service.logoutAllDevices(userId);

            assertThat(token1.isRevoked()).isTrue();
            assertThat(token2.isRevoked()).isTrue();
        }
    }
}