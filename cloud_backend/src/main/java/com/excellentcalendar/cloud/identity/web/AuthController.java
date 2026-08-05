package com.excellentcalendar.cloud.identity.web;

import com.excellentcalendar.cloud.identity.dto.request.ChangeEmailRequest;
import com.excellentcalendar.cloud.identity.dto.request.ChangePasswordRequest;
import com.excellentcalendar.cloud.identity.dto.request.ForgotPasswordRequest;
import com.excellentcalendar.cloud.identity.dto.request.LoginRequest;
import com.excellentcalendar.cloud.identity.dto.request.RefreshTokenRequest;
import com.excellentcalendar.cloud.identity.dto.request.ResetPasswordRequest;
import com.excellentcalendar.cloud.identity.dto.request.SignUpRequest;
import com.excellentcalendar.cloud.identity.dto.request.VerifyEmailRequest;
import com.excellentcalendar.cloud.identity.dto.response.AuthResponse;
import com.excellentcalendar.cloud.identity.dto.response.MessageResponse;
import com.excellentcalendar.cloud.identity.service.AuthenticationService;
import jakarta.validation.Valid;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping(path = "/api/v1/auth", produces = MediaType.APPLICATION_JSON_VALUE)
public class AuthController {

    private final AuthenticationService authenticationService;

    public AuthController(AuthenticationService authenticationService) {
        this.authenticationService = authenticationService;
    }

    @PostMapping("/signup")
    @ResponseStatus(HttpStatus.CREATED)
    public AuthResponse signUp(@Valid @RequestBody SignUpRequest request) {
        return authenticationService.signUp(request);
    }

    @PostMapping("/login")
    public AuthResponse login(@Valid @RequestBody LoginRequest request) {
        return authenticationService.login(request.email(), request.password());
    }

    @PostMapping("/refresh")
    public AuthResponse refresh(@Valid @RequestBody RefreshTokenRequest request) {
        return authenticationService.refreshToken(request.refreshToken());
    }

    @PostMapping("/verify-email")
    public AuthResponse verifyEmail(
            @AuthenticationPrincipal UUID userId,
            @Valid @RequestBody VerifyEmailRequest request) {
        return authenticationService.verifyEmail(userId, request.code());
    }

    @PostMapping("/resend-verification")
    public MessageResponse resendVerification(@AuthenticationPrincipal UUID userId) {
        authenticationService.resendVerificationCode(userId);
        return new MessageResponse("Verification code sent");
    }

    @PostMapping("/forgot-password")
    public MessageResponse forgotPassword(@Valid @RequestBody ForgotPasswordRequest request) {
        authenticationService.forgotPassword(request.email());
        return new MessageResponse(
                "If the email is registered, a password reset link has been sent.");
    }

    @PostMapping("/reset-password")
    public MessageResponse resetPassword(@Valid @RequestBody ResetPasswordRequest request) {
        authenticationService.resetPassword(request.code(), request.newPassword());
        return new MessageResponse("Password has been reset successfully.");
    }

    @PostMapping("/change-password")
    public AuthResponse changePassword(
            @AuthenticationPrincipal UUID userId,
            @Valid @RequestBody ChangePasswordRequest request) {
        return authenticationService.changePassword(userId, request.currentPassword(), request.newPassword());
    }

    @PostMapping("/change-email")
    public MessageResponse changeEmail(
            @AuthenticationPrincipal UUID userId,
            @Valid @RequestBody ChangeEmailRequest request) {
        authenticationService.requestEmailChange(userId, request.newEmail(), request.currentPassword());
        return new MessageResponse("Verification code sent to the new email address.");
    }

    @PostMapping("/logout")
    public MessageResponse logout(@Valid @RequestBody RefreshTokenRequest request) {
        authenticationService.logout(request.refreshToken());
        return new MessageResponse("Logged out successfully.");
    }

    @PostMapping("/logout-all")
    public MessageResponse logoutAll(@AuthenticationPrincipal UUID userId) {
        authenticationService.logoutAllDevices(userId);
        return new MessageResponse("Logged out from all devices.");
    }
}