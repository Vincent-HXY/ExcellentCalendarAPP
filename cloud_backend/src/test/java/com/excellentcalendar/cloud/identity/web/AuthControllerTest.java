package com.excellentcalendar.cloud.identity.web;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.excellentcalendar.cloud.identity.dto.response.AuthResponse;
import com.excellentcalendar.cloud.identity.service.AuthenticationService;
import com.excellentcalendar.cloud.identity.service.IdentityException;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.method.annotation.AuthenticationPrincipalArgumentResolver;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

@ExtendWith(MockitoExtension.class)
class AuthControllerTest {

    private MockMvc mockMvc;

    @Mock
    private AuthenticationService authenticationService;

    private final UUID userId = UUID.randomUUID();
    private final String accessToken = "access-token";
    private final String refreshToken = "refresh-token";

    @BeforeEach
    void setUp() {
        AuthController controller = new AuthController(authenticationService);
        mockMvc = MockMvcBuilders.standaloneSetup(controller)
                .setControllerAdvice(new IdentityExceptionHandler())
                .setCustomArgumentResolvers(new AuthenticationPrincipalArgumentResolver())
                .build();
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(
                        userId, null, List.of(new SimpleGrantedAuthority("ROLE_USER"))));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private AuthResponse validAuthResponse() {
        return new AuthResponse(userId, "test@example.com", "testuser", "Test User",
                null, "en", "UTC", true, accessToken, refreshToken, 900);
    }

    @Nested
    @DisplayName("POST /api/v1/auth/signup")
    class SignUp {

        @Test
        @DisplayName("should return 201 Created on successful signup")
        void shouldReturn201_whenSignupSucceeds() throws Exception {
            when(authenticationService.signUp(any())).thenReturn(validAuthResponse());

            mockMvc.perform(post("/api/v1/auth/signup")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("""
                                    {
                                        "email": "new@example.com",
                                        "username": "newuser",
                                        "displayName": "New User",
                                        "password": "password123"
                                    }
                                    """))
                    .andExpect(status().isCreated())
                    .andExpect(jsonPath("$.accessToken").value(accessToken));
        }

        @Test
        @DisplayName("should return 400 when validation fails")
        void shouldReturn400_whenValidationFails() throws Exception {
            mockMvc.perform(post("/api/v1/auth/signup")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("""
                                    {
                                        "email": "invalid",
                                        "username": "ab",
                                        "displayName": "",
                                        "password": "short"
                                    }
                                    """))
                    .andExpect(status().isBadRequest());
        }
    }

    @Nested
    @DisplayName("POST /api/v1/auth/login")
    class Login {

        @Test
        @DisplayName("should return 200 on successful login")
        void shouldReturn200_whenLoginSucceeds() throws Exception {
            when(authenticationService.login(eq("test@example.com"), eq("password123")))
                    .thenReturn(validAuthResponse());

            mockMvc.perform(post("/api/v1/auth/login")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("""
                                    {
                                        "email": "test@example.com",
                                        "password": "password123"
                                    }
                                    """))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.accessToken").value(accessToken));
        }

        @Test
        @DisplayName("should return 401 on invalid credentials")
        void shouldReturn401_whenInvalidCredentials() throws Exception {
            when(authenticationService.login(eq("test@example.com"), eq("wrong-password")))
                    .thenThrow(new IdentityException.InvalidCredentials("Invalid email or password"));

            mockMvc.perform(post("/api/v1/auth/login")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("""
                                    {
                                        "email": "test@example.com",
                                        "password": "wrong-password"
                                    }
                                    """))
                    .andExpect(status().isUnauthorized());
        }

        @Test
        @DisplayName("should return 403 on disabled account")
        void shouldReturn403_whenAccountDisabled() throws Exception {
            when(authenticationService.login(eq("disabled@example.com"), eq("password")))
                    .thenThrow(new IdentityException.AccountDisabled("Account is disabled"));

            mockMvc.perform(post("/api/v1/auth/login")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("""
                                    {
                                        "email": "disabled@example.com",
                                        "password": "password"
                                    }
                                    """))
                    .andExpect(status().isForbidden());
        }
    }

    @Nested
    @DisplayName("POST /api/v1/auth/refresh")
    class Refresh {

        @Test
        @DisplayName("should return 200 on successful refresh")
        void shouldReturn200_whenRefreshSucceeds() throws Exception {
            when(authenticationService.refreshToken("valid-refresh-token"))
                    .thenReturn(validAuthResponse());

            mockMvc.perform(post("/api/v1/auth/refresh")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("""
                                    {
                                        "refreshToken": "valid-refresh-token"
                                    }
                                    """))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.accessToken").value(accessToken));
        }

        @Test
        @DisplayName("should return 401 on invalid token")
        void shouldReturn401_whenInvalidToken() throws Exception {
            when(authenticationService.refreshToken("invalid-token"))
                    .thenThrow(new IdentityException.InvalidToken("Invalid refresh token"));

            mockMvc.perform(post("/api/v1/auth/refresh")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("""
                                    {
                                        "refreshToken": "invalid-token"
                                    }
                                    """))
                    .andExpect(status().isUnauthorized());
        }
    }

    @Nested
    @DisplayName("POST /api/v1/auth/verify-email / resend-verification / forgot-password / reset-password / change-password / change-email / logout / logout-all")
    class OtherEndpoints {

        @Test
        @DisplayName("should return 200 on successful verify-email")
        void shouldReturn200_whenVerifyEmail() throws Exception {
            when(authenticationService.verifyEmail(any(UUID.class), eq("123456")))
                    .thenReturn(validAuthResponse());

            mockMvc.perform(post("/api/v1/auth/verify-email")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("""
                                    {
                                        "code": "123456"
                                    }
                                    """))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.accessToken").value(accessToken));
        }

        @Test
        @DisplayName("should return 400 on invalid verification code")
        void shouldReturn400_whenInvalidCode() throws Exception {
            mockMvc.perform(post("/api/v1/auth/verify-email")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("""
                                    {
                                        "code": "invalid"
                                    }
                                    """))
                    .andExpect(status().isBadRequest());
        }

        @Test
        @DisplayName("should return 200 for resend-verification")
        void shouldReturn200_resendVerification() throws Exception {
            mockMvc.perform(post("/api/v1/auth/resend-verification"))
                    .andExpect(status().isOk());
        }

        @Test
        @DisplayName("should return 200 for forgot-password")
        void shouldReturn200_forgotPassword() throws Exception {
            mockMvc.perform(post("/api/v1/auth/forgot-password")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("""
                                    {
                                        "email": "test@example.com"
                                    }
                                    """))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.message").exists());
        }

        @Test
        @DisplayName("should return 200 for reset-password")
        void shouldReturn200_resetPassword() throws Exception {
            mockMvc.perform(post("/api/v1/auth/reset-password")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("""
                                    {
                                        "code": "123456",
                                        "newPassword": "new-password-123"
                                    }
                                    """))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.message").exists());
        }

        @Test
        @DisplayName("should return 200 for change-password")
        void shouldReturn200_changePassword() throws Exception {
            when(authenticationService.changePassword(any(UUID.class), eq("old-pass"), eq("new-pass-123")))
                    .thenReturn(validAuthResponse());

            mockMvc.perform(post("/api/v1/auth/change-password")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("""
                                    {
                                        "currentPassword": "old-pass",
                                        "newPassword": "new-pass-123"
                                    }
                                    """))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.accessToken").value(accessToken));
        }

        @Test
        @DisplayName("should return 200 for change-email")
        void shouldReturn200_changeEmail() throws Exception {
            mockMvc.perform(post("/api/v1/auth/change-email")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("""
                                    {
                                        "newEmail": "new@example.com",
                                        "currentPassword": "my-password"
                                    }
                                    """))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.message").exists());
        }

        @Test
        @DisplayName("should return 200 for logout")
        void shouldReturn200_logout() throws Exception {
            mockMvc.perform(post("/api/v1/auth/logout")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("""
                                    {
                                        "refreshToken": "some-token"
                                    }
                                    """))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.message").exists());
        }

        @Test
        @DisplayName("should return 200 for logout-all")
        void shouldReturn200_logoutAll() throws Exception {
            mockMvc.perform(post("/api/v1/auth/logout-all"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.message").exists());
        }
    }
}