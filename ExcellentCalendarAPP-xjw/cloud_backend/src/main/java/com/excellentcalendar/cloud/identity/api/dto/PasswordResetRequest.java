package com.excellentcalendar.cloud.identity.api.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * Maps to {@code contracts/auth/password_reset_request.schema.json}.
 */
public record PasswordResetRequest(
        @NotBlank @Email @Size(max = 254) String email
) {}