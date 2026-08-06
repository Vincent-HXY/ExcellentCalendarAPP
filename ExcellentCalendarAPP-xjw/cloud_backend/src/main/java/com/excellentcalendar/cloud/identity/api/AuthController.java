package com.excellentcalendar.cloud.identity.api;

import com.excellentcalendar.cloud.identity.api.dto.ChangePasswordRequest;
import com.excellentcalendar.cloud.identity.api.dto.ConfirmEmailChangeRequest;
import com.excellentcalendar.cloud.identity.api.dto.ConfirmPasswordResetRequest;
import com.excellentcalendar.cloud.identity.api.dto.EmailChangeRequest;
import com.excellentcalendar.cloud.identity.api.dto.LoginRequest;
import com.excellentcalendar.cloud.identity.api.dto.LogoutRequest;
import com.excellentcalendar.cloud.identity.api.dto.PasswordResetRequest;
import com.excellentcalendar.cloud.identity.api.dto.RefreshSessionRequest;
import com.excellentcalendar.cloud.identity.api.dto.RegistrationRequest;
import com.excellentcalendar.cloud.identity.api.dto.ResendRegistrationRequest;
import com.excellentcalendar.cloud.identity.api.dto.VerifyRegistrationRequest;
import com.excellentcalendar.cloud.identity.application.AuthenticationResult;
import com.excellentcalendar.cloud.identity.application.ChangePasswordUseCase;
import com.excellentcalendar.cloud.identity.application.EmailChangeConfirmUseCase;
import com.excellentcalendar.cloud.identity.application.EmailChangeRequestUseCase;
import com.excellentcalendar.cloud.identity.application.LoginUseCase;
import com.excellentcalendar.cloud.identity.application.LogoutAllUseCase;
import com.excellentcalendar.cloud.identity.application.LogoutUseCase;
import com.excellentcalendar.cloud.identity.application.PasswordResetConfirmUseCase;
import com.excellentcalendar.cloud.identity.application.PasswordResetRequestUseCase;
import com.excellentcalendar.cloud.identity.application.RefreshTokenUseCase;
import com.excellentcalendar.cloud.identity.application.RegisterUseCase;
import com.excellentcalendar.cloud.identity.application.ResendVerificationUseCase;
import com.excellentcalendar.cloud.identity.application.VerifyRegistrationUseCase;
import com.excellentcalendar.cloud.platform.api.ApiResult;
import com.excellentcalendar.cloud.platform.api.OperationResponse;
import com.excellentcalendar.cloud.platform.api.RequestIdUtils;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Controller for all authentication endpoints.
 * Base path: /api/v1/auth
 */
@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {

    private final RegisterUseCase registerUseCase;
    private final VerifyRegistrationUseCase verifyRegistrationUseCase;
    private final ResendVerificationUseCase resendVerificationUseCase;
    private final LoginUseCase loginUseCase;
    private final RefreshTokenUseCase refreshTokenUseCase;
    private final LogoutUseCase logoutUseCase;
    private final LogoutAllUseCase logoutAllUseCase;
    private final PasswordResetRequestUseCase passwordResetRequestUseCase;
    private final PasswordResetConfirmUseCase passwordResetConfirmUseCase;
    private final ChangePasswordUseCase changePasswordUseCase;
    private final EmailChangeRequestUseCase emailChangeRequestUseCase;
    private final EmailChangeConfirmUseCase emailChangeConfirmUseCase;

    public AuthController(
            RegisterUseCase registerUseCase,
            VerifyRegistrationUseCase verifyRegistrationUseCase,
            ResendVerificationUseCase resendVerificationUseCase,
            LoginUseCase loginUseCase,
            RefreshTokenUseCase refreshTokenUseCase,
            LogoutUseCase logoutUseCase,
            LogoutAllUseCase logoutAllUseCase,
            PasswordResetRequestUseCase passwordResetRequestUseCase,
            PasswordResetConfirmUseCase passwordResetConfirmUseCase,
            ChangePasswordUseCase changePasswordUseCase,
            EmailChangeRequestUseCase emailChangeRequestUseCase,
            EmailChangeConfirmUseCase emailChangeConfirmUseCase) {
        this.registerUseCase = registerUseCase;
        this.verifyRegistrationUseCase = verifyRegistrationUseCase;
        this.resendVerificationUseCase = resendVerificationUseCase;
        this.loginUseCase = loginUseCase;
        this.refreshTokenUseCase = refreshTokenUseCase;
        this.logoutUseCase = logoutUseCase;
        this.logoutAllUseCase = logoutAllUseCase;
        this.passwordResetRequestUseCase = passwordResetRequestUseCase;
        this.passwordResetConfirmUseCase = passwordResetConfirmUseCase;
        this.changePasswordUseCase = changePasswordUseCase;
        this.emailChangeRequestUseCase = emailChangeRequestUseCase;
        this.emailChangeConfirmUseCase = emailChangeConfirmUseCase;
    }

    // ==================== Registration ====================

    @PostMapping("/register")
    ResponseEntity<ApiResult<Map<String, Object>>> register(
            @Valid @RequestBody RegistrationRequest request,
            HttpServletRequest httpRequest) {
        var result = registerUseCase.register(
                request.email(), request.username(), request.displayName(),
                request.password(), request.locale(), request.timezone(),
                request.agreementVersion(), request.agreementAccepted());

        Map<String, Object> challenge = new HashMap<>();
        challenge.put("challenge_id", result.challengeId().toString());
        challenge.put("action_id", result.actionId() != null ? result.actionId().toString() : null);
        challenge.put("purpose", result.purpose());
        challenge.put("masked_email", result.maskedEmail());
        challenge.put("credential_types", result.credentialTypes());
        challenge.put("expires_at", result.expiresAt().toString());
        challenge.put("resend_available_at", result.resendAvailableAt().toString());

        Map<String, Object> data = new HashMap<>();
        data.put("account_id", result.accountId().toString());
        data.put("challenge", challenge);

        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApiResult.success(data, requestId(httpRequest)));
    }

    @PostMapping("/registration/verify")
    ResponseEntity<ApiResult<Map<String, Object>>> verifyRegistration(
            @Valid @RequestBody VerifyRegistrationRequest request,
            HttpServletRequest httpRequest) {
        var authResult = verifyRegistrationUseCase.verify(
                request.challengeId(), request.credential().credentialType(),
                request.credential().getCode());

        return ResponseEntity.ok(
                ApiResult.success(buildAuthenticationResponse(authResult), requestId(httpRequest)));
    }

    @PostMapping("/registration/resend")
    ResponseEntity<ApiResult<Map<String, Object>>> resendRegistration(
            @Valid @RequestBody ResendRegistrationRequest request,
            HttpServletRequest httpRequest) {
        var result = resendVerificationUseCase.resend(request.challengeId());

        Map<String, Object> data = new HashMap<>();
        data.put("challenge_id", result.challengeId().toString());
        data.put("action_id", result.actionId() != null ? result.actionId().toString() : null);
        data.put("purpose", result.purpose());
        data.put("masked_email", result.maskedEmail());
        data.put("credential_types", result.credentialTypes());
        data.put("expires_at", result.expiresAt().toString());
        data.put("resend_available_at", result.resendAvailableAt().toString());

        return ResponseEntity.ok(ApiResult.success(data, requestId(httpRequest)));
    }

    // ==================== Login ====================

    @PostMapping("/login")
    ResponseEntity<ApiResult<Map<String, Object>>> login(
            @Valid @RequestBody LoginRequest request,
            HttpServletRequest httpRequest) {
        var authResult = loginUseCase.login(request.email(), request.password());
        return ResponseEntity.ok(
                ApiResult.success(buildAuthenticationResponse(authResult), requestId(httpRequest)));
    }

    // ==================== Token Refresh ====================

    @PostMapping("/token/refresh")
    ResponseEntity<ApiResult<Map<String, Object>>> refreshToken(
            @Valid @RequestBody RefreshSessionRequest request,
            HttpServletRequest httpRequest) {
        var tokenPair = refreshTokenUseCase.refresh(request.refreshToken());

        Map<String, Object> data = new HashMap<>();
        data.put("token_type", "Bearer");
        data.put("access_token", tokenPair.accessToken());
        data.put("access_token_expires_at", tokenPair.accessTokenExpiresAt().toString());
        data.put("refresh_token", tokenPair.refreshToken());
        data.put("refresh_token_expires_at", tokenPair.refreshTokenExpiresAt().toString());
        data.put("session_id", tokenPair.sessionId().toString());

        return ResponseEntity.ok(ApiResult.success(data, requestId(httpRequest)));
    }

    // ==================== Logout ====================

    @PostMapping("/logout")
    ResponseEntity<ApiResult<OperationResponse>> logout(
            @Valid @RequestBody LogoutRequest request,
            HttpServletRequest httpRequest) {
        logoutUseCase.logout(request.refreshToken());
        return ResponseEntity.ok(
                ApiResult.success(OperationResponse.success(), requestId(httpRequest)));
    }

    @PostMapping("/logout-all")
    ResponseEntity<ApiResult<OperationResponse>> logoutAll(
            @AuthenticationPrincipal UUID userId,
            HttpServletRequest httpRequest) {
        logoutAllUseCase.logoutAll(userId);
        return ResponseEntity.ok(
                ApiResult.success(OperationResponse.success(), requestId(httpRequest)));
    }

    // ==================== Password Reset ====================

    @PostMapping("/password-reset/request")
    ResponseEntity<ApiResult<Map<String, Object>>> requestPasswordReset(
            @Valid @RequestBody PasswordResetRequest request,
            HttpServletRequest httpRequest) {
        var result = passwordResetRequestUseCase.requestReset(request.email());

        Map<String, Object> data = new HashMap<>();
        data.put("accepted", result.accepted());
        data.put("resend_available_at", result.resendAvailableAt().toString());

        return ResponseEntity.ok(ApiResult.success(data, requestId(httpRequest)));
    }

    @PostMapping("/password-reset/confirm")
    ResponseEntity<ApiResult<OperationResponse>> confirmPasswordReset(
            @Valid @RequestBody ConfirmPasswordResetRequest request,
            HttpServletRequest httpRequest) {
        passwordResetConfirmUseCase.confirmReset(
                request.email(), request.credential().getCode(), request.newPassword());
        return ResponseEntity.ok(
                ApiResult.success(OperationResponse.success(), requestId(httpRequest)));
    }

    // ==================== Password Change ====================

    @PostMapping("/password/change")
    ResponseEntity<ApiResult<Map<String, Object>>> changePassword(
            @Valid @RequestBody ChangePasswordRequest request,
            @AuthenticationPrincipal UUID userId,
            HttpServletRequest httpRequest) {
        var authResult = changePasswordUseCase.changePassword(
                userId, extractSessionId(httpRequest),
                request.currentPassword(), request.newPassword());
        return ResponseEntity.ok(
                ApiResult.success(buildAuthenticationResponse(authResult), requestId(httpRequest)));
    }

    // ==================== Email Change ====================

    @PostMapping("/email-change/request")
    ResponseEntity<ApiResult<Map<String, Object>>> requestEmailChange(
            @Valid @RequestBody EmailChangeRequest request,
            @AuthenticationPrincipal UUID userId,
            HttpServletRequest httpRequest) {
        var result = emailChangeRequestUseCase.requestEmailChange(
                userId, request.newEmail(), request.currentPassword());

        Map<String, Object> data = new HashMap<>();
        data.put("challenge_id", result.challengeId().toString());
        data.put("action_id", result.actionId().toString());
        data.put("purpose", result.purpose());
        data.put("masked_email", result.maskedEmail());
        data.put("credential_types", result.credentialTypes());
        data.put("expires_at", result.expiresAt().toString());
        data.put("resend_available_at", result.resendAvailableAt().toString());

        return ResponseEntity.ok(ApiResult.success(data, requestId(httpRequest)));
    }

    @PostMapping("/email-change/confirm")
    ResponseEntity<ApiResult<Map<String, Object>>> confirmEmailChange(
            @Valid @RequestBody ConfirmEmailChangeRequest request,
            @AuthenticationPrincipal UUID userId,
            HttpServletRequest httpRequest) {
        var authResult = emailChangeConfirmUseCase.confirmEmailChange(
                userId, request.emailChangeRequestId(),
                extractChallengeId(request), request.credential().credentialType(),
                request.credential().getCode());
        return ResponseEntity.ok(
                ApiResult.success(buildAuthenticationResponse(authResult), requestId(httpRequest)));
    }

    // ==================== Helpers ====================

    private static Map<String, Object> buildAuthenticationResponse(AuthenticationResult result) {
        Map<String, Object> account = new HashMap<>();
        account.put("id", result.userId().toString());
        account.put("email", result.email());
        account.put("status", result.emailVerified() ? "active" : "pending_verification");
        account.put("email_verified_at", result.emailVerified() ? result.accessTokenExpiresAt().toString() : null);
        account.put("created_at", result.accessTokenExpiresAt().toString());
        account.put("updated_at", result.accessTokenExpiresAt().toString());

        Map<String, Object> profile = new HashMap<>();
        profile.put("user_id", result.userId().toString());
        profile.put("username", result.username());
        profile.put("display_name", result.displayName());
        profile.put("avatar", null);
        profile.put("created_at", result.accessTokenExpiresAt().toString());
        profile.put("updated_at", result.accessTokenExpiresAt().toString());

        Map<String, Object> preferences = new HashMap<>();
        preferences.put("user_id", result.userId().toString());
        preferences.put("locale", "zh-CN");
        preferences.put("timezone", "Asia/Shanghai");
        preferences.put("default_reminder_methods", List.of("popup"));
        preferences.put("settings", Map.of("theme", "system"));
        preferences.put("created_at", result.accessTokenExpiresAt().toString());
        preferences.put("updated_at", result.accessTokenExpiresAt().toString());

        Map<String, Object> tokens = new HashMap<>();
        tokens.put("token_type", "Bearer");
        tokens.put("access_token", result.accessToken());
        tokens.put("access_token_expires_at", result.accessTokenExpiresAt().toString());
        tokens.put("refresh_token", result.refreshToken());
        tokens.put("refresh_token_expires_at", result.refreshTokenExpiresAt().toString());
        tokens.put("session_id", result.sessionId().toString());

        Map<String, Object> currentUser = new HashMap<>();
        currentUser.put("account", account);
        currentUser.put("profile", profile);
        currentUser.put("preferences", preferences);

        Map<String, Object> response = new HashMap<>();
        response.put("current_user", currentUser);
        response.put("tokens", tokens);

        return response;
    }

    private static UUID extractChallengeId(ConfirmEmailChangeRequest request) {
        return request.emailChangeRequestId();
    }

    private static UUID extractSessionId(HttpServletRequest request) {
        return UUID.randomUUID();
    }

    private static String requestId(HttpServletRequest request) {
        return RequestIdUtils.getRequestId(request);
    }
}